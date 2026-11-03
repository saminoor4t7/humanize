import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../core/constants/protocol_constants.dart';
import '../core/errors/app_exceptions.dart';
import '../core/utilities/hash_utils.dart';
import '../core/utilities/speed_meter.dart';
import '../models/transfer.dart';
import 'peer_handshake.dart';
import 'security_service.dart';
import 'tcp_client.dart';

/// SERVICE: runs ONE outgoing transfer (all files of one request) over one
/// TLS connection. Never throws: the outcome is written into [transfer].
///
/// Sequence: connect -> authenticate -> TRANSFER_REQUEST -> wait for the
/// user's decision -> for each file { FILE_START, CHUNK*, FILE_END, wait
/// FILE_RESULT } -> SESSION_DONE.
class TransferSender {
  TransferSender({
    required this.transfer,
    required this.security,
    required this.localName,
    required this.localPort,
    required this.host,
    required this.port,
    required this.chunkSize,
    required this.onProgress,
    this.expectedPeerId,
    this.debugAbortAfterBytes,
  });

  final Transfer transfer;
  final SecurityService security;
  final String localName;
  final int localPort;
  final String host;
  final int port;
  final int chunkSize;
  final void Function() onProgress;
  final String? expectedPeerId;

  /// Test hook: simulate a dropped network after this many bytes were sent.
  final int? debugAbortAfterBytes;

  PeerChannel? _channel;
  bool _cancelled = false;
  final SpeedMeter _meter = SpeedMeter();
  int _sessionSent = 0;
  int _completedBytes = 0;

  void cancel() {
    _cancelled = true;
    // While connecting/waiting nothing polls the flag, so cut the connection.
    if (transfer.state != TransferState.transferring) _channel?.destroy();
  }

  void _checkCancelled() {
    if (_cancelled) throw const TransferCancelledException('Cancelled.');
  }

  Future<void> run() async {
    try {
      transfer.state = TransferState.connecting;
      onProgress();

      final channel = await TcpClient.connect(
        host: host,
        port: port,
        context: security.clientContext(),
      );
      _channel = channel;
      _checkCancelled();

      final peer = await PeerHandshake.asClient(
        reader: channel.reader,
        writer: channel.writer,
        security: security,
        localName: localName,
        localPort: localPort,
        serverTlsFingerprint: channel.serverCertFingerprint,
        remoteIp: channel.remoteIp,
        expectedPeerId: expectedPeerId ?? transfer.peerId,
      );
      transfer.peerId = peer.id;
      transfer.peerName = peer.name;
      _checkCancelled();

      await channel.writer.writeJson(ProtocolConstants.transferRequest, {
        'v': ProtocolConstants.version,
        'transferId': transfer.id,
        'totalBytes': transfer.totalBytes,
        'files': [
          for (final f in transfer.files)
            {'index': f.index, 'fileKey': f.fileKey, 'relPath': f.relPath, 'size': f.size},
        ],
      });
      transfer.state = TransferState.awaitingApproval;
      onProgress();

      final response = await channel.reader.next(timeout: ProtocolConstants.approvalWait);
      _checkCancelled();
      if (response.type == ProtocolConstants.error) {
        throw ProtocolException(response.json()['message']?.toString() ?? 'Error from receiver.');
      }
      if (response.type != ProtocolConstants.transferResponse) {
        throw const ProtocolException('Unexpected reply to the transfer request.');
      }
      final r = response.json();
      if (r['accepted'] != true) {
        transfer.state = TransferState.rejected;
        transfer.error = r['reason']?.toString() ?? 'The other computer declined the transfer.';
        return;
      }
      final resume = (r['resume'] is Map) ? (r['resume'] as Map).cast<String, dynamic>() : <String, dynamic>{};

      transfer.state = TransferState.transferring;
      transfer.startedAt = DateTime.now();
      onProgress();

      for (final file in transfer.files) {
        await _sendFile(channel, file, resume[file.fileKey]);
        _completedBytes += file.size;
        transfer.completedFiles++;
      }
      await channel.writer.writeJson(ProtocolConstants.sessionDone, {});

      transfer.transferredBytes = transfer.totalBytes;
      transfer.speedBytesPerSecond = 0;
      transfer.state = TransferState.completed;
    } on TransferCancelledException {
      await _notifyCancel();
      transfer.state = TransferState.cancelled;
      transfer.error = null;
    } on HumanizeException catch (e) {
      _fail(e.message);
    } on SocketException catch (e) {
      await _explainSocketFailure(e);
    } on FileSystemException catch (e) {
      _fail('File problem: ${e.message}${e.path != null ? ' (${e.path})' : ''}');
    } catch (e) {
      _fail('Unexpected error: $e');
    } finally {
      transfer.endedAt = DateTime.now();
      transfer.currentFile = null;
      transfer.speedBytesPerSecond = 0;
      _channel?.destroy();
      onProgress();
    }
  }

  void _fail(String message) {
    // A user cancel that raced with a socket error is still a cancel.
    if (_cancelled) {
      transfer.state = TransferState.cancelled;
      return;
    }
    transfer.state = TransferState.failed;
    transfer.error = message;
  }

  /// A write failed: the receiver may have cancelled and closed. Look for a
  /// CANCEL frame it sent before closing so the message is accurate.
  Future<void> _explainSocketFailure(SocketException e) async {
    if (_cancelled) {
      transfer.state = TransferState.cancelled;
      return;
    }
    final channel = _channel;
    if (channel != null && transfer.state == TransferState.transferring) {
      try {
        for (var i = 0; i < 8; i++) {
          final f = await channel.reader.readFrame(timeout: const Duration(seconds: 1));
          if (f == null) break;
          if (f.type == ProtocolConstants.cancel) {
            transfer.state = TransferState.cancelled;
            transfer.error = 'Cancelled by the other computer.';
            return;
          }
        }
      } catch (_) {}
    }
    _fail('Connection lost: ${e.osError?.message ?? e.message}');
  }

  Future<void> _notifyCancel() async {
    final channel = _channel;
    if (channel == null) return;
    try {
      await channel.writer
          .writeJson(ProtocolConstants.cancel, {'reason': 'Cancelled by sender'})
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  Future<void> _sendFile(PeerChannel channel, TransferFile f, Object? resumeEntry) async {
    final path = f.localPath;
    if (path == null) throw const HumanizeException('Internal error: missing file path.');
    final file = File(path);
    transfer.currentFile = f.relPath;

    // The file must be exactly what the user picked.
    final stat = await file.stat();
    if (stat.type == FileSystemEntityType.notFound) {
      throw HumanizeException('"${f.relPath}" no longer exists.');
    }
    if (stat.size != f.size ||
        (f.modifiedMs != null && stat.modified.millisecondsSinceEpoch != f.modifiedMs)) {
      throw HumanizeException('"${f.relPath}" changed after it was selected. Select it again.');
    }

    // Resume: receiver tells us how much it has and the hash of that prefix.
    // We only continue if OUR first N bytes hash identically.
    var offset = 0;
    Sha256Accumulator? running;
    if (resumeEntry is Map) {
      final remoteOffset = resumeEntry['offset'];
      final remoteHash = resumeEntry['sha256'];
      if (remoteOffset is int && remoteHash is String && remoteOffset > 0 && remoteOffset < f.size) {
        final ph = await hashPrefix(file, remoteOffset);
        if (ph.prefixHex == remoteHash) {
          offset = remoteOffset;
          running = ph.running;
        }
      }
    }
    running ??= Sha256Accumulator();
    transfer.resumedBytes += offset;
    transfer.transferredBytes = _completedBytes + offset;
    onProgress();

    await channel.writer.writeJson(
        ProtocolConstants.fileStart, {'index': f.index, 'offset': offset});

    final raf = await file.open();
    try {
      await raf.setPosition(offset);
      var position = offset;
      while (position < f.size) {
        _checkCancelled();
        final want = min(chunkSize, f.size - position);
        final Uint8List data = await raf.read(want);
        if (data.length != want) {
          throw HumanizeException('"${f.relPath}" changed while it was being sent.');
        }
        running.add(data); // full-file SHA-256, computed as we go
        await channel.writer.writeBytes(ProtocolConstants.chunk, data);
        position += data.length;
        _sessionSent += data.length;

        transfer.transferredBytes = _completedBytes + position;
        _meter.record(_sessionSent); // speed from real bytes sent
        transfer.speedBytesPerSecond = _meter.bytesPerSecond;
        onProgress();

        final abortAt = debugAbortAfterBytes;
        if (abortAt != null && _sessionSent >= abortAt) {
          throw const SocketException('Simulated network failure');
        }
      }
    } finally {
      await raf.close();
    }

    await channel.writer.writeJson(ProtocolConstants.fileEnd, {
      'index': f.index,
      'size': f.size,
      'sha256': running.closeHex(),
    });

    // The file is only "sent" once the receiver verified its SHA-256.
    final result = await channel.reader.next(timeout: ProtocolConstants.idleTimeout);
    if (result.type == ProtocolConstants.cancel) {
      throw const TransferCancelledException('Cancelled by the other computer.');
    }
    if (result.type != ProtocolConstants.fileResult) {
      throw const ProtocolException('Unexpected reply after file data.');
    }
    final rj = result.json();
    if (rj['ok'] != true) {
      throw IntegrityException(
          'The other computer could not accept "${f.relPath}": ${rj['error'] ?? 'verification failed'}.');
    }
  }
}
