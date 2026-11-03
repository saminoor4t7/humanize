import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/constants/protocol_constants.dart';
import '../core/errors/app_exceptions.dart';
import '../core/utilities/fingerprint.dart';
import '../core/utilities/hash_utils.dart';
import '../core/utilities/path_sanitizer.dart';
import '../core/utilities/speed_meter.dart';
import '../models/app_settings.dart';
import '../models/transfer.dart';
import '../models/transfer_request.dart';
import 'partial_store.dart';
import 'peer_handshake.dart';
import 'security_service.dart';
import 'tcp_client.dart';
import 'trust_store.dart';

/// What an incoming session needs from the service that owns it.
/// (An interface keeps the session free of UI/ViewModel knowledge and lets
/// tests provide a tiny fake.)
abstract class IncomingHost {
  AppSettings get settings;
  SecurityService get security;
  TrustStore get trustStore;

  /// Shows the request to the user and resolves with their decision.
  Future<bool> requestApproval(TransferRequest request);

  bool tryAcquireIncomingSlot();
  void releaseIncomingSlot();

  /// Lets the host list the transfer and cancel it later.
  void registerTransfer(Transfer transfer, void Function() cancel);
  void notifyProgress();
  void transferFinished(Transfer transfer);
}

class _ParsedRequest {
  _ParsedRequest(this.transferId, this.files, this.segments);
  final String transferId;
  final List<TransferFile> files;
  final Map<int, List<String>> segments; // validated path segments per file index
}

/// SERVICE: handles ONE incoming connection from handshake to completion.
///
/// Safety rules enforced here:
///  * nothing is written before the user (or an explicit trust policy) approves;
///  * every path is validated and resolved inside the download folder;
///  * data goes to a hidden partial file and is renamed only after SHA-256
///    and size verification succeed;
///  * received files are never executed or opened.
class IncomingSession {
  IncomingSession({required this.channel, required this.host});

  final PeerChannel channel;
  final IncomingHost host;

  bool _cancelled = false;
  Transfer? _transfer;
  bool _slotHeld = false;
  final SpeedMeter _meter = SpeedMeter();
  int _sessionReceived = 0;
  int _completedBytes = 0;
  String _peerId = '';
  PartialStore? _store;
  List<TransferFile> _files = const [];

  void cancel() {
    _cancelled = true;
    final t = _transfer;
    // Before data flows nothing polls the flag, so cut the connection.
    if (t != null && t.state != TransferState.transferring) channel.destroy();
  }

  Future<void> run() async {
    final settings = host.settings;
    try {
      final peer = await PeerHandshake.asServer(
        reader: channel.reader,
        writer: channel.writer,
        security: host.security,
        localName: settings.deviceName,
        remoteIp: channel.remoteIp,
      );
      _peerId = peer.id;

      final first = await channel.reader.readFrame(timeout: ProtocolConstants.idleTimeout);
      // A probe (manual add) authenticates and hangs up: not an error.
      if (first == null) return;
      if (first.type != ProtocolConstants.transferRequest) {
        throw const ProtocolException('Expected a transfer request.');
      }

      _ParsedRequest parsed;
      try {
        parsed = _parseRequest(first.json(), settings);
      } on HumanizeException catch (e) {
        await _respondReject(e.message);
        return;
      }
      _files = parsed.files;

      final trusted = host.trustStore.isTrusted(peer.id);
      final transfer = Transfer(
        id: 'in-${parsed.transferId}',
        direction: TransferDirection.incoming,
        peerName: peer.name,
        peerIp: peer.ip,
        peerId: peer.id,
        files: parsed.files,
        state: TransferState.awaitingApproval,
      )..peerTrusted = trusted;
      _transfer = transfer;
      host.registerTransfer(transfer, cancel);

      // ---- Authorization: explicit approval unless trusted + policy on ----
      final request = TransferRequest(
        id: transfer.id,
        peerId: peer.id,
        peerName: peer.name,
        peerIp: peer.ip,
        trusted: trusted,
        files: parsed.files,
      );
      final autoAccept = trusted && settings.autoAcceptTrusted;
      final approved = autoAccept ? true : await host.requestApproval(request);
      if (_cancelled) throw const TransferCancelledException('Cancelled.');
      if (!approved) {
        transfer.state = TransferState.rejected;
        transfer.error = 'You declined this transfer.';
        await _respondReject('The other computer declined the transfer.');
        return;
      }
      if (!host.tryAcquireIncomingSlot()) {
        transfer.state = TransferState.rejected;
        transfer.error = 'Too many simultaneous transfers.';
        await _respondReject('The receiver is busy with too many transfers. Try again shortly.');
        return;
      }
      _slotHeld = true;

      // ---- Prepare destination and resume information ----
      final downloadDir = settings.downloadDir;
      await Directory(downloadDir).create(recursive: true);
      final store = PartialStore(downloadDir);
      _store = store;

      final resumeInfo = <String, PartialState>{};
      for (final f in parsed.files) {
        final st = await store.inspect(peer.id, f.fileKey, f.size);
        if (st != null) resumeInfo[f.fileKey] = st;
      }
      await channel.writer.writeJson(ProtocolConstants.transferResponse, {
        'transferId': parsed.transferId,
        'accepted': true,
        'resume': {
          for (final e in resumeInfo.entries)
            e.key: {'offset': e.value.offset, 'sha256': e.value.prefixSha256},
        },
      });

      transfer.state = TransferState.transferring;
      transfer.startedAt = DateTime.now();
      host.notifyProgress();

      for (final f in parsed.files) {
        final frame = await channel.reader.next(timeout: ProtocolConstants.idleTimeout);
        if (frame.type == ProtocolConstants.cancel) {
          throw const TransferCancelledException('Cancelled by the other computer.');
        }
        if (frame.type != ProtocolConstants.fileStart) {
          throw const ProtocolException('Expected the start of a file.');
        }
        final j = frame.json();
        if (j['index'] != f.index) {
          throw const ProtocolException('Files arrived out of order.');
        }
        final offset = j['offset'];
        if (offset is! int || offset < 0 || (f.size == 0 ? offset != 0 : offset >= f.size)) {
          throw const ProtocolException('Invalid resume offset.');
        }
        final resumed = offset > 0 ? resumeInfo[f.fileKey] : null;
        if (offset > 0 && (resumed == null || resumed.offset != offset)) {
          throw const ProtocolException('Sender asked to resume from an unknown position.');
        }
        await _receiveFile(f, offset, resumed, parsed.segments[f.index]!, store);
        _completedBytes += f.size;
        transfer.completedFiles++;
      }

      // Sender sends SESSION_DONE (or just closes). Either is fine.
      try {
        await channel.reader.readFrame(timeout: const Duration(seconds: 5));
      } catch (_) {}

      transfer.transferredBytes = transfer.totalBytes;
      transfer.state = TransferState.completed;
    } on TransferCancelledException {
      await _onCancelled();
    } on IntegrityException catch (e) {
      _fail(e.message);
    } on HumanizeException catch (e) {
      // Interrupted transfers keep their partial files so they can resume.
      _fail(e.message);
    } on SocketException catch (e) {
      _fail('Connection lost: ${e.osError?.message ?? e.message}');
    } on FileSystemException catch (e) {
      _fail('Could not write the file: ${e.message}${e.path != null ? ' (${e.path})' : ''}');
      await _tryNotifyError('Receiver could not write the file.');
    } catch (e) {
      _fail('Unexpected error: $e');
    } finally {
      final t = _transfer;
      if (t != null) {
        t.endedAt = DateTime.now();
        t.currentFile = null;
        t.speedBytesPerSecond = 0;
      }
      if (_slotHeld) host.releaseIncomingSlot();
      channel.destroy();
      if (t != null) host.transferFinished(t);
    }
  }

  void _fail(String message) {
    final t = _transfer;
    if (t == null) return; // failed before a transfer existed (e.g. probe)
    if (_cancelled) {
      t.state = TransferState.cancelled;
      return;
    }
    if (t.state.isActive) {
      t.state = TransferState.failed;
      t.error = message;
    }
  }

  Future<void> _onCancelled() async {
    final t = _transfer;
    if (t != null) {
      t.state = TransferState.cancelled;
      t.error = null;
    }
    try {
      await channel.writer
          .writeJson(ProtocolConstants.cancel, {'reason': 'Cancelled by receiver'})
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
    // User cancel means: do not keep half-downloaded data around.
    final store = _store;
    if (store != null && _cancelled) {
      for (final f in _files) {
        await store.discard(_peerId, f.fileKey);
      }
    }
  }

  Future<void> _respondReject(String reason) async {
    try {
      await channel.writer.writeJson(ProtocolConstants.transferResponse, {
        'accepted': false,
        'reason': reason,
      });
    } catch (_) {}
  }

  Future<void> _tryNotifyError(String message) async {
    try {
      await channel.writer
          .writeJson(ProtocolConstants.error, {'code': 'io', 'message': message})
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  // ---- request validation ----

  _ParsedRequest _parseRequest(Map<String, dynamic> m, AppSettings settings) {
    final id = m['transferId'];
    if (id is! String || !RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) {
      throw const ProtocolException('Invalid transfer ID.');
    }
    final rawFiles = m['files'];
    if (rawFiles is! List || rawFiles.isEmpty) {
      throw const ProtocolException('The request contains no files.');
    }
    if (rawFiles.length > ProtocolConstants.maxFilesPerTransfer) {
      throw const ProtocolException('Too many files in one transfer.');
    }
    final files = <TransferFile>[];
    final segments = <int, List<String>>{};
    final seen = <String>{};
    for (var i = 0; i < rawFiles.length; i++) {
      final raw = rawFiles[i];
      if (raw is! Map) throw const ProtocolException('Malformed file entry.');
      final index = raw['index'];
      final fileKey = raw['fileKey'];
      final relPath = raw['relPath'];
      final size = raw['size'];
      if (index != i || fileKey is! String || !Fingerprint.isValid(fileKey) ||
          relPath is! String || size is! int || size < 0) {
        throw const ProtocolException('Malformed file entry.');
      }
      final segs = PathSanitizer.splitAndValidate(relPath); // throws on unsafe names
      if (size > settings.maxFileSizeBytes) {
        throw HumanizeException(
            '"${segs.last}" is larger than this computer accepts (${settings.maxFileSizeMb} MB limit).');
      }
      if (!seen.add(segs.join('/').toLowerCase())) {
        throw const ProtocolException('Duplicate file names in one transfer.');
      }
      segments[i] = segs;
      files.add(TransferFile(index: i, fileKey: fileKey, relPath: segs.join('/'), size: size));
    }
    return _ParsedRequest(id, files, segments);
  }

  // ---- receiving one file ----

  Future<void> _receiveFile(
    TransferFile f,
    int offset,
    PartialState? resumed,
    List<String> segments,
    PartialStore store,
  ) async {
    final transfer = _transfer!;
    transfer.currentFile = f.relPath;
    transfer.resumedBytes += offset;
    transfer.transferredBytes = _completedBytes + offset;
    host.notifyProgress();

    // Final destination decided (and re-validated) up front.
    final destRoot = store.downloadDir;
    PathSanitizer.resolveInside(destRoot, segments);

    final hash = offset == 0 ? Sha256Accumulator() : resumed!.running;
    await store.begin(_peerId, f.fileKey, f.relPath, f.size);
    final part = store.partFile(_peerId, f.fileKey);

    // offset == 0 truncates any stale partial; otherwise append after the
    // validated prefix.
    final raf = await part.open(mode: offset == 0 ? FileMode.write : FileMode.append);
    var received = offset;
    try {
      while (received < f.size) {
        if (_cancelled) throw const TransferCancelledException('Cancelled.');
        final frame = await channel.reader.next(timeout: ProtocolConstants.idleTimeout);
        if (frame.type == ProtocolConstants.cancel) {
          throw const TransferCancelledException('Cancelled by the other computer.');
        }
        if (frame.type != ProtocolConstants.chunk) {
          throw const ProtocolException('Expected file data.');
        }
        final data = frame.payload;
        // Never accept more bytes than the manifest promised.
        if (data.isEmpty || received + data.length > f.size) {
          throw const ProtocolException('Received an unexpected amount of data.');
        }
        await raf.writeFrom(data);
        hash.add(data);
        received += data.length;
        _sessionReceived += data.length;

        transfer.transferredBytes = _completedBytes + received;
        _meter.record(_sessionReceived);
        transfer.speedBytesPerSecond = _meter.bytesPerSecond;
        host.notifyProgress();
      }
      await raf.flush();
    } finally {
      await raf.close();
    }

    final endFrame = await channel.reader.next(timeout: ProtocolConstants.idleTimeout);
    if (endFrame.type == ProtocolConstants.cancel) {
      throw const TransferCancelledException('Cancelled by the other computer.');
    }
    if (endFrame.type != ProtocolConstants.fileEnd) {
      throw const ProtocolException('Expected the end of a file.');
    }
    final e = endFrame.json();
    final declaredHash = (e['sha256'] is String) ? (e['sha256'] as String).toLowerCase() : '';
    final actualHash = hash.closeHex();
    final onDisk = await part.length();

    if (e['index'] != f.index || e['size'] != f.size || onDisk != f.size || declaredHash != actualHash) {
      // Corrupted: delete it (no point keeping bad data) and tell the sender.
      await store.discard(_peerId, f.fileKey);
      try {
        await channel.writer.writeJson(ProtocolConstants.fileResult, {
          'index': f.index,
          'ok': false,
          'error': 'Checksum mismatch: the file arrived damaged.',
        });
      } catch (_) {}
      throw IntegrityException(
          '"${f.relPath}" failed SHA-256 verification and was discarded.');
    }

    // Verified: move into place (same volume, so rename is atomic).
    final finalPath = PathSanitizer.uniquePath(PathSanitizer.resolveInside(destRoot, segments));
    await Directory(p.dirname(finalPath)).create(recursive: true);
    await part.rename(finalPath);
    await store.deleteMeta(_peerId, f.fileKey);
    await channel.writer.writeJson(ProtocolConstants.fileResult, {'index': f.index, 'ok': true});
  }
}
