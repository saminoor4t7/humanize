import 'package:flutter/foundation.dart';

import '../core/utilities/network_info.dart';
import '../models/transfer_record.dart';
import 'device_viewmodel.dart';
import 'history_viewmodel.dart';
import 'settings_viewmodel.dart';
import 'transfer_viewmodel.dart';

/// VIEWMODEL: derives dashboard numbers from the other ViewModels (real state).
class DashboardViewModel extends ChangeNotifier {
  DashboardViewModel({
    required SettingsViewModel settingsVm,
    required DeviceViewModel deviceVm,
    required TransferViewModel transferVm,
    required HistoryViewModel historyVm,
  })  : _settingsVm = settingsVm,
        _deviceVm = deviceVm,
        _transferVm = transferVm,
        _historyVm = historyVm {
    for (final l in _sources) {
      l.addListener(notifyListeners);
    }
  }

  final SettingsViewModel _settingsVm;
  final DeviceViewModel _deviceVm;
  final TransferViewModel _transferVm;
  final HistoryViewModel _historyVm;

  List<Listenable> get _sources => [_settingsVm, _deviceVm, _transferVm, _historyVm];

  String? _localIp;
  bool _loadingNetwork = true;

  String get deviceName => _settingsVm.settings.deviceName;
  String? get localIp => _localIp;
  bool get loadingNetwork => _loadingNetwork;
  bool get isOnLan => _localIp != null;

  int get discoveredDevices => _deviceVm.onlineCount;
  int get activeTransfers => _transferVm.activeCount;
  int get completedTransfers => _historyVm.completedCount;
  int get totalBytesTransferred => _historyVm.totalBytesTransferred;
  List<TransferRecord> get recentTransfers => _historyVm.recent;

  bool get isListening => _transferVm.isListening;
  int get listeningPort => _transferVm.listeningPort;
  String? get serverError => _transferVm.serverError;

  Future<void> refreshNetwork() async {
    _loadingNetwork = true;
    notifyListeners();
    _localIp = await NetworkInfo.findLocalIPv4();
    _loadingNetwork = false;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final l in _sources) {
      l.removeListener(notifyListeners);
    }
    super.dispose();
  }
}
