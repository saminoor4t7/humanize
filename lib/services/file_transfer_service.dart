import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../core/errors/app_exceptions.dart';
import '../models/app_settings.dart';
import '../models/transfer.dart';
import '../models/transfer_record.dart';
import '../models/transfer_request.dart';
import '../core/constants/protocol_constants.dart';
import 'history_service.dart';
import 'incoming_session.dart';
import 'partial_store.dart';
import 'peer_handshake.dart';
import 'security_service.dart';
import 'tcp_client.dart';
import 'tcp_server.dart';
import 'transfer_sender.dart';
import 'trust_store.dart';

enum ServiceEventKind { info, success, error, incomingRequest }

/// A short message for the UI layer (shown as a notification).
class ServiceEvent {
  const ServiceEvent(this.kind, this.message);
  final ServiceEventKind kind;
  final String message;
}

class _QueuedSend {
  _QueuedSend(this.transfer, this.host, this.port, this.expectedPeerId, this.abortAfter);
  final Transfer transfer;
  final String host;
  final int port;
  final String? expectedPeerId;
  final int? abortAfter;
}

/// SERVICE: orchestrates the receiving server and all transfers.
/// It owns no UI. ViewModels listen to [changes] and [events] and call
/// [send], [accept], [reject] and [cancel].
class FileTransferService implements IncomingHost {
  FileTransferService({
    required this.security,
    required this.trustStore,
    required this.history,
    required AppSettings Function() readSettings,
  }) : _readSettings = readSettings;

  @override
  final SecurityService security;
  @override
  final TrustStore trustStore;
  final HistoryService history;
  final AppSettings Function() _readSettings;

  final TcpServer _server = TcpServer();
  final List<Transfer> _transfers = []; // newest first
  final List<TransferRequest> _pending = [];
  final Map<String, void Function()> _cancelHooks = {};
  final Queue<_QueuedSend> _queue = Queue();

  int _activeOutgoing = 0;
  int _activeIncoming = 0;
  Timer? _notifyTimer;
  bool _disposed = false;

  final StreamController<void> _changes = StreamController<void>.broadcast();
  final StreamController<ServiceEvent> _events = StreamController<ServiceEvent>.broadcast();

  /// Last server start failure (e.g. port already in use), or null.
  String? serverError;
  bool get isListening => _server.isRunning;
  int get listeningPort => _server.port;

  Stream<void> get changes => _changes.stream;
  Stream<ServiceEvent> get events => _events.stream;
  List<Transfer> get transfers => List.unmodifiable(_transfers);
  List<TransferRequest> get pendingRequests => List.unmodifiable(_pending);

  @override
  AppSettings get settings => _readSettings();

  // ---------------------------------------------------------------- server

  Future<void> start({int? portOverride}) async {
    serverError = null;
    final port = portOverride ?? settings.port;
    try {
      await _server.start(
        port: port,
        context: security.serverContext(),
        onConnection: _onConnection,
      );
      unawaited(PartialStore(settings.downloadDir).purgeExpired());
    } on Object catch (e) {
      serverError = 'Could not listen on port $port: ${_friendly(e)}. '
          'Another program may be using it. Change the port in Settings.';
      _emit(ServiceEventKind.error, serverError!);
    }
    _notifyNow();
  }

  Future<void> stop() async {
    await _server.stop();
    _notifyNow();
  }

  Future<void> restart() async {
    await stop();
    await start();
  }

  /// Called when settings change so a new port takes effect immediately.
  Future<void> applySettings(AppSettings before, AppSettings after) async {
    if (before.port != after.port) await restart();
  }

  void _onConnection(SecureSocket socket) {
    final session = IncomingSession(channel: PeerChannel(socket), host: this);
    unawaited(session.run());
  }

  // -------------------------------------------------------- IncomingHost

  @override
  Future<bool> requestApproval(TransferRequest request) {
    _pending.add(request);
    _emit(ServiceEventKind.incomingRequest,
        '${request.peerName} wants to send ${request.files.length} file${request.files.length == 1 ? '' : 's'}.');
    _notifyNow();
    return request.decision.future
        .timeout(ProtocolConstants.approvalTimeout, onTimeout: () => false)
        .whenComplete(() {
      _pending.remove(request);
      _notifyNow();
    });
  }

  @override
  bool tryAcquireIncomingSlot() {
    if (_activeIncoming >= settings.maxConcurrentTransfers) return false;
    _activeIncoming++;
    return true;
  }

  @override
  void releaseIncomingSlot() {
    if (_activeIncoming > 0) _activeIncoming--;
  }

  @override
  void registerTransfer(Transfer transfer, void Function() cancel) {
    _transfers.insert(0, transfer);
    _cancelHooks[transfer.id] = cancel;
    _trimFinished();
    _notifyNow();
  }

  @override
  void notifyProgress() => _notifyThrottled();

  @override
  void transferFinished(Transfer transfer) {
    _cancelHooks.remove(transfer.id);
    _finish(transfer);
  }

  /// Approve / decline from the UI.
  void accept(String requestId) {
    for (final r in _pending) {
      if (r.id == requestId) r.accept();
    }
  }

  void reject(String requestId) {
    for (final r in _pending) {
      if (r.id == requestId) r.reject();
    }
  }

  // --------------------------------------------------------------- sending

  /// Queues a transfer. Runs when a concurrency slot is free.
  Transfer send({
    required String host,
    required int port,
    required List<SendFile> files,
    String? peerName,
    String? expectedPeerId,
    int? debugAbortAfterBytes,
  }) {
    final transferId = _randomHex(16);
    final transfer = Transfer(
      id: transferId,
      direction: TransferDirection.outgoing,
      peerName: peerName ?? host,
      peerIp: host,
      peerId: expectedPeerId,
      files: [
        for (var i = 0; i < files.length; i++)
          TransferFile(
            index: i,
            fileKey: _fileKey(files[i]),
            relPath: files[i].relPath,
            size: files[i].size,
            localPath: files[i].localPath,
            modifiedMs: files[i].modifiedMs,
          ),
      ],
    );
    _transfers.insert(0, transfer);
    _queue.add(_QueuedSend(transfer, host, port, expectedPeerId, debugAbortAfterBytes));
    _trimFinished();
    _pumpQueue();
    _notifyNow();
    return transfer;
  }

  /// Same file + same size + same timestamp => same key, so an interrupted
  /// transfer can be resumed by sending the same selection again.
  static String _fileKey(SendFile f) => sha256
      .convert(utf8.encode('${f.relPath}|${f.size}|${f.modifiedMs}'))
      .toString();

  void _pumpQueue() {
    while (!_disposed && _queue.isNotEmpty && _activeOutgoing < max(1, settings.maxConcurrentTransfers)) {
      final job = _queue.removeFirst();
      if (job.transfer.state != TransferState.queued) continue; // cancelled while waiting
      _activeOutgoing++;
      final s = settings;
      final sender = TransferSender(
        transfer: job.transfer,
        security: security,
        localName: s.deviceName,
        localPort: s.port,
        host: job.host,
        port: job.port,
        chunkSize: s.chunkSizeBytes,
        expectedPeerId: job.expectedPeerId,
        debugAbortAfterBytes: job.abortAfter,
        onProgress: _notifyThrottled,
      );
      _cancelHooks[job.transfer.id] = sender.cancel;
      sender.run().whenComplete(() {
        _activeOutgoing--;
        _cancelHooks.remove(job.transfer.id);
        _finish(job.transfer);
        _pumpQueue();
      });
    }
  }

  /// Connects, authenticates, and returns who is at [host]:[port].
  /// Used by "Add device by IP"; transfers nothing.
  Future<PeerInfo> probe(String host, int port) async {
    final channel = await TcpClient.connect(
      host: host,
      port: port,
      context: security.clientContext(),
    );
    try {
      return await PeerHandshake.asClient(
        reader: channel.reader,
        writer: channel.writer,
        security: security,
        localName: settings.deviceName,
        localPort: settings.port,
        serverTlsFingerprint: channel.serverCertFingerprint,
        remoteIp: channel.remoteIp,
      );
    } finally {
      channel.destroy();
    }
  }

  // ------------------------------------------------------------- cancel

  void cancel(String transferId) {
    final t = _transfers.where((x) => x.id == transferId).firstOrNull;
    if (t == null || !t.state.isActive) return;
    if (t.state == TransferState.queued) {
      t.state = TransferState.cancelled;
      t.endedAt = DateTime.now();
      _finish(t);
      return;
    }
    // If the user is still deciding, cancelling means declining.
    for (final r in _pending) {
      if (r.id == transferId) r.reject();
    }
    _cancelHooks[transferId]?.call();
  }

  // -------------------------------------------------------- bookkeeping

  final Set<String> _recorded = {};

  void _finish(Transfer t) {
    if (!_recorded.add(t.id)) return; // record each transfer once
    _notifyNow();
    final status = switch (t.state) {
      TransferState.completed => TransferStatus.completed,
      TransferState.cancelled => TransferStatus.cancelled,
      TransferState.rejected => TransferStatus.rejected,
      _ => TransferStatus.failed,
    };
    final bytes = status == TransferStatus.completed ? t.totalBytes : t.transferredBytes;
    // Duration/speed use the time actually spent transferring.
    final duration = t.elapsed;
    unawaited(history.add(TransferRecord(
      id: t.id,
      fileName: t.displayName,
      fileCount: t.files.length,
      sizeBytes: bytes,
      peerName: t.peerName,
      peerIp: t.peerIp,
      isOutgoing: t.isOutgoing,
      finishedAt: t.endedAt ?? DateTime.now(),
      duration: duration,
      status: status,
      error: t.error,
    )));
    final dir = t.isOutgoing ? 'to' : 'from';
    switch (status) {
      case TransferStatus.completed:
        _emit(ServiceEventKind.success,
            '${t.isOutgoing ? 'Sent' : 'Received'} ${t.displayName} $dir ${t.peerName}.');
      case TransferStatus.failed:
        _emit(ServiceEventKind.error, 'Transfer $dir ${t.peerName} failed: ${t.error ?? 'unknown error'}');
      case TransferStatus.rejected:
        if (t.isOutgoing) {
          _emit(ServiceEventKind.error, '${t.peerName} declined the transfer: ${t.error ?? ''}');
        }
      case TransferStatus.cancelled:
        break;
    }
  }

  void _trimFinished() {
    // Keep the in-session list bounded; history holds the permanent record.
    final finished = _transfers.where((t) => !t.state.isActive).toList();
    if (finished.length > 100) {
      for (final t in finished.sublist(100)) {
        _transfers.remove(t);
      }
    }
  }

  void _emit(ServiceEventKind kind, String message) {
    if (!_events.isClosed) _events.add(ServiceEvent(kind, message));
  }

  void _notifyNow() {
    _notifyTimer?.cancel();
    _notifyTimer = null;
    if (!_changes.isClosed) _changes.add(null);
  }

  /// Progress updates arrive per chunk; coalesce them to ~10 UI updates/second.
  void _notifyThrottled() {
    if (_notifyTimer != null || _changes.isClosed) return;
    _notifyTimer = Timer(const Duration(milliseconds: 100), () {
      _notifyTimer = null;
      if (!_changes.isClosed) _changes.add(null);
    });
  }

  static final Random _rng = Random.secure();
  static String _randomHex(int bytes) =>
      List<int>.generate(bytes, (_) => _rng.nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

  String _friendly(Object e) => e is HumanizeException ? e.message : e.toString();

  Future<void> dispose() async {
    _disposed = true;
    for (final hook in _cancelHooks.values.toList()) {
      hook();
    }
    for (final r in _pending.toList()) {
      r.reject();
    }
    await _server.stop();
    _notifyTimer?.cancel();
    await _changes.close();
    await _events.close();
  }
}
