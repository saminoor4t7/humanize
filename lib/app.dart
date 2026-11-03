import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'viewmodels/settings_viewmodel.dart';
import 'views/shell/app_shell.dart';

class HumanizeApp extends StatelessWidget {
  const HumanizeApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilds only when the theme mode changes.
    final mode = context.select<SettingsViewModel, ThemeMode>((vm) => vm.settings.themeMode);
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      home: const AppShell(),
    );
  }
}
