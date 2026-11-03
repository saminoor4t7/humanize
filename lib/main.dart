import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'services/discovery_service.dart';
import 'services/file_transfer_service.dart';
import 'services/history_service.dart';
import 'services/security_service.dart';
import 'services/settings_service.dart';
import 'services/startup_service.dart';
import 'services/trust_store.dart';
import 'viewmodels/dashboard_viewmodel.dart';
import 'viewmodels/device_viewmodel.dart';
import 'viewmodels/history_viewmodel.dart';
import 'viewmodels/navigation_viewmodel.dart';
import 'viewmodels/send_viewmodel.dart';
import 'viewmodels/settings_viewmodel.dart';
import 'viewmodels/transfer_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Composition root (MVVM wiring):
///   Services are created once here, injected into ViewModels, and the
///   ViewModels are exposed to Views through Provider.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final settingsService = SettingsService(prefs);
  final initialSettings = await settingsService.load();

  final security = await SecurityService.loadOrCreate();
  final trustStore = TrustStore(prefs);
  final history = await HistoryService.open();

  final settingsVm = SettingsViewModel(settingsService, initialSettings, startup: StartupService());

  final transferService = FileTransferService(
    security: security,
    trustStore: trustStore,
    history: history,
    readSettings: () => settingsVm.settings,
  );
  final discovery = DiscoveryService(
    selfId: security.identity.id,
    localName: () => settingsVm.settings.deviceName,
    localPort: () => settingsVm.settings.port,
  );

  final transferVm = TransferViewModel(transferService, settingsVm);
  final deviceVm = DeviceViewModel(
    discovery: discovery,
    trustStore: trustStore,
    transfers: transferService,
    settingsVm: settingsVm,
  );
  final historyVm = HistoryViewModel(history);

  // Start the receiver and discovery without blocking the first frame.
  unawaited(transferVm.start());
  unawaited(deviceVm.start());

  runApp(
    MultiProvider(
      providers: [
        Provider<SecurityService>.value(value: security),
        ChangeNotifierProvider<SettingsViewModel>.value(value: settingsVm),
        ChangeNotifierProvider<TransferViewModel>.value(value: transferVm),
        ChangeNotifierProvider<DeviceViewModel>.value(value: deviceVm),
        ChangeNotifierProvider<HistoryViewModel>.value(value: historyVm),
        ChangeNotifierProvider(create: (_) => NavigationViewModel()),
        ChangeNotifierProvider(create: (_) => SendViewModel(transferVm, deviceVm)),
        ChangeNotifierProvider(
          create: (_) => DashboardViewModel(
            settingsVm: settingsVm,
            deviceVm: deviceVm,
            transferVm: transferVm,
            historyVm: historyVm,
          )..refreshNetwork(),
        ),
      ],
      child: const HumanizeApp(),
    ),
  );
}
