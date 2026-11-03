import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/constants/protocol_constants.dart';
import '../core/errors/app_exceptions.dart';
import '../core/utilities/network_info.dart';
import '../models/device.dart';
import '../services/discovery_service.dart';
import '../services/file_transfer_service.dart';
import '../services/trust_store.dart';
import 'settings_viewmodel.dart';

/// A device plus the facts the UI needs about it.
class DeviceView {
  const DeviceView({required this.device, required this.online, required this.trusted});
  final Device device;
  final bool online;
  final bool trusted;
}

/// VIEWMODEL: discovered devices, trust decisions, manual add.
class DeviceViewModel extends ChangeNotifier {
  DeviceViewModel({
    required DiscoveryService discovery,
    required TrustStore trustStore,
    required FileTransferService transfers,
    required SettingsViewModel settingsVm,
  })  : _discovery = discovery,
        _trust = trustStore,
        _transfers = transfers,
        _settingsVm = settingsVm {
    _subs.add(_discovery.devices.listen((_) => notifyListeners()));
    _subs.add(_trust.changes.listen((_) => notifyListeners()));
    _settingsVm.addListener(_onSettings);
    _discoveryWanted = _settingsVm.settings.discoveryEnabled;
  }

  final DiscoveryService _discovery;
  final TrustStore _trust;
  final FileTransferService _transfers;
  final SettingsViewModel _settingsVm;
  final List<StreamSubscription<Object?>> _subs = [];

  bool _discoveryWanted = false;
  String? _discoveryError;
  bool _busy = false;

  String? get discoveryError => _discoveryError;
  bool get discoveryRunning => _discovery.isRunning;
  bool get busy => _busy;

  List<DeviceView> get devices {
    final now = DateTime.now();
    return [
      for (final d in _discovery.currentDevices)
        DeviceView(
          device: d,
          online: d.isOnline(now, ProtocolConstants.deviceOfflineAfter),
          trusted: _trust.isTrusted(d.id),
        ),
    ];
  }

  int get onlineCount => devices.where((d) => d.online).length;
  List<TrustedDevice> get trustedDevices => _trust.devices;

  Future<void> start() async {
    if (_discoveryWanted) await _startDiscovery();
  }

  Future<void> _startDiscovery() async {
    try {
      await _discovery.start();
      _discoveryError = null;
    } catch (e) {
      _discoveryError = 'Device discovery could not start: $e';
    }
    notifyListeners();
  }

  void _onSettings() {
    final wanted = _settingsVm.settings.discoveryEnabled;
    if (wanted == _discoveryWanted) return;
    _discoveryWanted = wanted;
    if (wanted) {
      unawaited(_startDiscovery());
    } else {
      unawaited(_discovery.stop().then((_) => notifyListeners()));
    }
  }

  Future<void> refresh() async {
    if (!_discovery.isRunning) await _startDiscovery();
    await _discovery.refresh();
    notifyListeners();
  }

  Future<void> trust(Device d) => _trust.trust(d.id, d.name);
  Future<void> untrust(String id) => _trust.remove(id);

  /// Validates input, connects, proves the device's identity, then lists it.
  /// Returns null on success or an error message.
  Future<String?> addManual(String host, String portText) async {
    final h = host.trim();
    final port = int.tryParse(portText.trim());
    if (!NetworkInfo.isValidIPv4(h)) return 'Enter a valid IPv4 address, like 192.168.1.20.';
    if (!NetworkInfo.isPrivateOrLoopbackIPv4(h)) {
      return 'Only local-network addresses are allowed (10.x, 172.16-31.x, 192.168.x).';
    }
    if (port == null || port < 1 || port > 65535) return 'Enter a port between 1 and 65535.';

    _busy = true;
    notifyListeners();
    try {
      final peer = await _transfers.probe(h, port);
      _discovery.addManual(Device(
        id: peer.id,
        name: peer.name,
        ip: h,
        port: port,
        lastSeen: DateTime.now(),
        isManual: true,
      ));
      return null;
    } on HumanizeException catch (e) {
      return e.message;
    } catch (e) {
      return 'Could not add the device: $e';
    } finally {
      _busy = false;
      notifyListeners();
    }
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
