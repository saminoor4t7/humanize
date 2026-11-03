import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';

/// MODEL: immutable application settings. No logic, no UI, no I/O.
@immutable
class AppSettings {
  const AppSettings({
    required this.deviceName,
    required this.port,
    required this.downloadDir,
    required this.themeMode,
    required this.launchAtStartup,
    required this.maxConcurrentTransfers,
    required this.maxFileSizeMb,
    required this.discoveryEnabled,
    required this.notificationsEnabled,
    this.autoAcceptTrusted = false,
    this.chunkSizeKb = AppConstants.defaultChunkSizeKb,
  });

  final String deviceName;
  final int port;
  final String downloadDir;
  final ThemeMode themeMode;
  final bool launchAtStartup;
  final int maxConcurrentTransfers;
  final int maxFileSizeMb;
  final bool discoveryEnabled;
  final bool notificationsEnabled;

  /// Trusted-device policy: skip the approval prompt for devices the user
  /// explicitly trusted. OFF by default.
  final bool autoAcceptTrusted;
  final int chunkSizeKb;

  int get maxFileSizeBytes => maxFileSizeMb * 1024 * 1024;
  int get chunkSizeBytes => chunkSizeKb * 1024;

  AppSettings copyWith({
    String? deviceName,
    int? port,
    String? downloadDir,
    ThemeMode? themeMode,
    bool? launchAtStartup,
    int? maxConcurrentTransfers,
    int? maxFileSizeMb,
    bool? discoveryEnabled,
    bool? notificationsEnabled,
    bool? autoAcceptTrusted,
    int? chunkSizeKb,
  }) {
    return AppSettings(
      deviceName: deviceName ?? this.deviceName,
      port: port ?? this.port,
      downloadDir: downloadDir ?? this.downloadDir,
      themeMode: themeMode ?? this.themeMode,
      launchAtStartup: launchAtStartup ?? this.launchAtStartup,
      maxConcurrentTransfers:
          maxConcurrentTransfers ?? this.maxConcurrentTransfers,
      maxFileSizeMb: maxFileSizeMb ?? this.maxFileSizeMb,
      discoveryEnabled: discoveryEnabled ?? this.discoveryEnabled,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      autoAcceptTrusted: autoAcceptTrusted ?? this.autoAcceptTrusted,
      chunkSizeKb: chunkSizeKb ?? this.chunkSizeKb,
    );
  }
}
