import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../models/app_settings.dart';

/// SERVICE (data layer): persists settings. Knows nothing about UI.
/// ViewModels call this; Views never do.
class SettingsService {
  SettingsService(this._prefs);

  final SharedPreferences _prefs;

  static Future<SettingsService> create() async =>
      SettingsService(await SharedPreferences.getInstance());

  static const _kName = 'deviceName';
  static const _kPort = 'port';
  static const _kDir = 'downloadDir';
  static const _kTheme = 'themeMode';
  static const _kStartup = 'launchAtStartup';
  static const _kConcurrent = 'maxConcurrentTransfers';
  static const _kMaxSize = 'maxFileSizeMb';
  static const _kDiscovery = 'discoveryEnabled';
  static const _kNotify = 'notificationsEnabled';
  static const _kAutoAccept = 'autoAcceptTrusted';
  static const _kChunk = 'chunkSizeKb';

  /// Loads saved settings, falling back to real machine-derived defaults.
  Future<AppSettings> load() async {
    final d = await _defaults();
    final themeIndex = _prefs.getInt(_kTheme);
    return AppSettings(
      deviceName: _prefs.getString(_kName) ?? d.deviceName,
      port: _prefs.getInt(_kPort) ?? d.port,
      downloadDir: _prefs.getString(_kDir) ?? d.downloadDir,
      themeMode: themeIndex != null &&
              themeIndex >= 0 &&
              themeIndex < ThemeMode.values.length
          ? ThemeMode.values[themeIndex]
          : d.themeMode,
      launchAtStartup: _prefs.getBool(_kStartup) ?? d.launchAtStartup,
      maxConcurrentTransfers: _prefs.getInt(_kConcurrent) ?? d.maxConcurrentTransfers,
      maxFileSizeMb: _prefs.getInt(_kMaxSize) ?? d.maxFileSizeMb,
      discoveryEnabled: _prefs.getBool(_kDiscovery) ?? d.discoveryEnabled,
      notificationsEnabled: _prefs.getBool(_kNotify) ?? d.notificationsEnabled,
      autoAcceptTrusted: _prefs.getBool(_kAutoAccept) ?? d.autoAcceptTrusted,
      chunkSizeKb: _prefs.getInt(_kChunk) ?? d.chunkSizeKb,
    );
  }

  Future<void> save(AppSettings s) async {
    await _prefs.setString(_kName, s.deviceName);
    await _prefs.setInt(_kPort, s.port);
    await _prefs.setString(_kDir, s.downloadDir);
    await _prefs.setInt(_kTheme, s.themeMode.index);
    await _prefs.setBool(_kStartup, s.launchAtStartup);
    await _prefs.setInt(_kConcurrent, s.maxConcurrentTransfers);
    await _prefs.setInt(_kMaxSize, s.maxFileSizeMb);
    await _prefs.setBool(_kDiscovery, s.discoveryEnabled);
    await _prefs.setBool(_kNotify, s.notificationsEnabled);
    await _prefs.setBool(_kAutoAccept, s.autoAcceptTrusted);
    await _prefs.setInt(_kChunk, s.chunkSizeKb);
  }

  Future<AppSettings> _defaults() async {
    String dir;
    try {
      dir = (await getDownloadsDirectory())?.path ??
          (await getApplicationDocumentsDirectory()).path;
    } catch (_) {
      dir = Directory.current.path;
    }
    return AppSettings(
      deviceName: Platform.localHostname,
      port: AppConstants.defaultPort,
      downloadDir: dir,
      themeMode: ThemeMode.system,
      launchAtStartup: false,
      maxConcurrentTransfers: AppConstants.defaultMaxConcurrentTransfers,
      maxFileSizeMb: AppConstants.defaultMaxFileSizeMb,
      discoveryEnabled: true,
      notificationsEnabled: true,
      autoAcceptTrusted: false,
      chunkSizeKb: AppConstants.defaultChunkSizeKb,
    );
  }
}
