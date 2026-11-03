import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../models/app_settings.dart';
import '../services/settings_service.dart';
import '../services/startup_service.dart';

/// VIEWMODEL: owns settings state + validation rules.
/// The View binds to this; it never touches SettingsService directly.
class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel(this._service, AppSettings initial, {StartupService? startup})
      : _settings = initial,
        _startup = startup;

  final SettingsService _service;
  final StartupService? _startup;
  AppSettings _settings;

  AppSettings get settings => _settings;
  bool get startupSupported => _startup?.isSupported ?? false;

  /// Validates then persists. Returns null on success, or an error message.
  Future<String?> save(AppSettings next) async {
    final error = validateAll(next);
    if (error != null) return error;

    // Windows startup entry is a side effect: apply it first so a failure
    // leaves the saved state honest.
    if (next.launchAtStartup != _settings.launchAtStartup && _startup != null) {
      final startupError = await _startup.setEnabled(next.launchAtStartup);
      if (startupError != null) return startupError;
    }
    await _service.save(next);
    _settings = next;
    notifyListeners();
    return null;
  }

  /// Applies a change that needs no form validation (e.g. folder picked).
  Future<void> update(AppSettings next) async {
    await _service.save(next);
    _settings = next;
    notifyListeners();
  }

  // ---- Validation rules (pure, unit-testable) ----

  static String? validateDeviceName(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Enter a computer name.';
    if (t.length > 40) return 'Name must be 40 characters or fewer.';
    if (RegExp(r'[\x00-\x1F]').hasMatch(t)) return 'Name contains invalid characters.';
    return null;
  }

  static String? validatePort(String? v) {
    final n = int.tryParse(v?.trim() ?? '');
    if (n == null) return 'Port must be a number.';
    if (n < AppConstants.minPort || n > AppConstants.maxPort) {
      return 'Use a port between ${AppConstants.minPort} and ${AppConstants.maxPort}.';
    }
    return null;
  }

  static String? validateDownloadDir(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Choose a download folder.';
    return null;
  }

  static String? validateConcurrent(String? v) {
    final n = int.tryParse(v?.trim() ?? '');
    if (n == null || n < 1 || n > AppConstants.maxConcurrentTransfersLimit) {
      return 'Enter 1 to ${AppConstants.maxConcurrentTransfersLimit}.';
    }
    return null;
  }

  static String? validateMaxFileSizeMb(String? v) {
    final n = int.tryParse(v?.trim() ?? '');
    if (n == null || n < 1 || n > AppConstants.maxFileSizeMbLimit) {
      return 'Enter 1 to ${AppConstants.maxFileSizeMbLimit} MB.';
    }
    return null;
  }

  static String? validateChunkSizeKb(String? v) {
    final n = int.tryParse(v?.trim() ?? '');
    if (n == null || n < AppConstants.minChunkSizeKb || n > AppConstants.maxChunkSizeKb) {
      return 'Enter ${AppConstants.minChunkSizeKb} to ${AppConstants.maxChunkSizeKb} KB.';
    }
    return null;
  }

  static String? validateAll(AppSettings s) {
    return validateDeviceName(s.deviceName) ??
        validatePort('${s.port}') ??
        validateDownloadDir(s.downloadDir) ??
        validateConcurrent('${s.maxConcurrentTransfers}') ??
        validateMaxFileSizeMb('${s.maxFileSizeMb}') ??
        validateChunkSizeKb('${s.chunkSizeKb}');
  }
}
