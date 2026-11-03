import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/transfer.dart';
import '../models/transfer_request.dart';
import '../services/file_transfer_service.dart';
import 'settings_viewmodel.dart';

/// VIEWMODEL: live transfers, incoming requests and the server status.
class TransferViewModel extends ChangeNotifier {
  TransferViewModel(this._service, this._settingsVm) {
    _subs.add(_service.changes.listen((_) => notifyListeners()));
    _lastSettings = _settingsVm.settings;
    _settingsVm.addListener(_onSettings);
  }

  final FileTransferService _service;
  final SettingsViewModel _settingsVm;
  final List<StreamSubscription<Object?>> _subs = [];
  late AppSettings _lastSettings;

  Stream<ServiceEvent> get events => _service.events;

  List<Transfer> get all => _service.transfers;
  List<Transfer> get outgoing => all.where((t) => t.isOutgoing).toList();
  List<Transfer> get incoming => all.where((t) => !t.isOutgoing).toList();
  List<Transfer> get active => all.where((t) => t.state.isActive).toList();
  int get activeCount => all.where((t) => t.state.isActive).length;
  List<TransferRequest> get pendingRequests => _service.pendingRequests;

  bool get isListening => _service.isListening;
  int get listeningPort => _service.listeningPort;
  String? get serverError => _service.serverError;

  Future<void> start() async {
    await _service.start();
    notifyListeners();
  }

  void accept(String requestId) => _service.accept(requestId);
  void reject(String requestId) => _service.reject(requestId);
  void cancel(String transferId) => _service.cancel(transferId);

  Transfer send({
    required String host,
    required int port,
    required List<SendFile> files,
    String? peerName,
    String? expectedPeerId,
  }) =>
      _service.send(
        host: host,
        port: port,
        files: files,
        peerName: peerName,
        expectedPeerId: expectedPeerId,
      );

  void _onSettings() {
    final next = _settingsVm.settings;
    final before = _lastSettings;
    _lastSettings = next;
    unawaited(_service.applySettings(before, next).then((_) => notifyListeners()));
  }

  @override
  void dispose() {
    _settingsVm.removeListener(_onSettings);
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}
