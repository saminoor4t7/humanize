import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humanize/core/constants/app_constants.dart';
import 'package:humanize/core/errors/app_exceptions.dart';
import 'package:humanize/core/utilities/fingerprint.dart';
import 'package:humanize/core/utilities/format_utils.dart';
import 'package:humanize/core/utilities/hash_utils.dart';
import 'package:humanize/core/utilities/network_info.dart';
import 'package:humanize/core/utilities/path_sanitizer.dart';
import 'package:humanize/core/utilities/speed_meter.dart';
import 'package:humanize/models/app_settings.dart';
import 'package:humanize/services/discovery_service.dart';
import 'package:humanize/services/settings_service.dart';
import 'package:humanize/viewmodels/settings_viewmodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _id1 = 'a' * 64;
final _id2 = 'b' * 64;

void main() {
  group('PathSanitizer (invalid filenames / path traversal)', () {
    test('accepts spaces and Unicode', () {
      expect(PathSanitizer.splitAndValidate('My Report (final).pdf'), ['My Report (final).pdf']);
      expect(PathSanitizer.splitAndValidate('Fotos/Zürich/日本語 ファイル.txt'),
          ['Fotos', 'Zürich', '日本語 ファイル.txt']);
    });

    for (final bad in [
      '../evil.txt', 'a/../../evil', '..\\evil', '/etc/passwd', '\\\\server\\share',
      'C:\\Windows\\x.dll', 'a/./b', 'a//b', '', 'con', 'NUL.txt', 'file.', 'file ',
      'a<b', 'a|b', 'a?b', 'a*b', 'a\u0000b', '.humanize-partial/x',
    ]) {
      test('rejects ${bad.replaceAll('\u0000', r'\0')}', () {
        expect(() => PathSanitizer.splitAndValidate(bad), throwsA(isA<PathValidationException>()));
      });
    }

    test('resolveInside keeps paths in the root', () {
      final root = Directory.systemTemp.path;
      expect(PathSanitizer.resolveInside(root, ['a', 'b.txt']).startsWith(root), isTrue);
      expect(() => PathSanitizer.resolveInside(root, ['..', 'x']),
          throwsA(isA<PathValidationException>()));
    });

    test('uniquePath never overwrites', () async {
      final dir = await Directory.systemTemp.createTemp('hz_unique');
      final f = File('${dir.path}${Platform.pathSeparator}a.txt')..writeAsStringSync('x');
      final next = PathSanitizer.uniquePath(f.path);
      expect(next, isNot(f.path));
      expect(next.endsWith('a (1).txt'), isTrue);
      await dir.delete(recursive: true);
    });
  });

  group('SHA-256 helpers', () {
    test('known vectors and prefix hashing', () async {
      final acc = Sha256Accumulator()..add('abc'.codeUnits);
      expect(acc.closeHex(), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      expect((Sha256Accumulator()..add(<int>[])).closeHex(),
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');

      final dir = await Directory.systemTemp.createTemp('hz_hash');
      final f = File('${dir.path}${Platform.pathSeparator}x')..writeAsStringSync('abcdef');
      final ph = await hashPrefix(f, 3);
      expect(ph.prefixHex, 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      ph.running.add('def'.codeUnits); // continuing yields the full-file hash
      final full = Sha256Accumulator()..add('abcdef'.codeUnits);
      expect(ph.running.closeHex(), full.closeHex());
      await dir.delete(recursive: true);
    });
  });

  group('Misc utilities', () {
    test('private IPv4 detection', () {
      expect(NetworkInfo.isPrivateIPv4('192.168.1.20'), isTrue);
      expect(NetworkInfo.isPrivateIPv4('10.0.0.5'), isTrue);
      expect(NetworkInfo.isPrivateIPv4('172.20.1.1'), isTrue);
      expect(NetworkInfo.isPrivateIPv4('172.32.0.1'), isFalse);
      expect(NetworkInfo.isPrivateIPv4('8.8.8.8'), isFalse);
      expect(NetworkInfo.isPrivateIPv4('300.1.1.1'), isFalse);
      expect(NetworkInfo.isPrivateOrLoopbackIPv4('127.0.0.1'), isTrue);
      expect(NetworkInfo.isPrivateOrLoopbackIPv4('1.1.1.1'), isFalse);
    });

    test('formatting', () {
      expect(FormatUtils.bytes(0), '0 B');
      expect(FormatUtils.bytes(1536), '1.5 KB');
      expect(FormatUtils.speed(10 * 1024 * 1024), '10.0 MB/s');
    });

    test('SpeedMeter measures real bytes over time', () {
      var now = DateTime(2026, 1, 1);
      final m = SpeedMeter(clock: () => now);
      m.record(0);
      now = now.add(const Duration(seconds: 2));
      m.record(20 * 1024 * 1024);
      expect(m.bytesPerSecond, closeTo(10 * 1024 * 1024, 1));
    });

    test('Fingerprint validation', () {
      expect(Fingerprint.isValid(_id1), isTrue);
      expect(Fingerprint.isValid('xyz'), isFalse);
      expect(Fingerprint.short(_id1), 'AAAA-AAAA-AAAA-AAAA');
    });
  });

  group('Discovery', () {
    DiscoveryService make() => DiscoveryService(
          selfId: _id1,
          localName: () => 'Me',
          localPort: () => 52525,
        );

    test('valid messages are parsed, junk is ignored', () {
      final good = DiscoveryMessage(kind: 'announce', id: _id2, name: 'Bob PC', port: 52525).encode();
      expect(DiscoveryMessage.parse(good), isNotNull);
      expect(DiscoveryMessage.parse('garbage'.codeUnits), isNull);
      expect(DiscoveryMessage.parse(List.filled(2000, 65)), isNull);
      expect(DiscoveryMessage.parse('{"app":"other"}'.codeUnits), isNull);
      expect(
          DiscoveryMessage.parse(
              '{"app":"humanize","v":1,"kind":"announce","id":"short","name":"x","port":5}'.codeUnits),
          isNull);
      expect(
          DiscoveryMessage.parse(
              '{"app":"humanize","v":1,"kind":"announce","id":"$_id2","name":"x","port":99999}'.codeUnits),
          isNull);
    });

    test('duplicate announcements produce one device', () {
      final s = make();
      final msg = DiscoveryMessage(kind: 'announce', id: _id2, name: 'Bob', port: 52525);
      expect(s.ingest(msg, '192.168.1.5'), isTrue);
      expect(s.ingest(msg, '192.168.1.5'), isTrue);
      expect(s.ingest(DiscoveryMessage(kind: 'announce', id: _id2, name: 'Bob (renamed)', port: 52525), '192.168.1.9'), isTrue);
      expect(s.currentDevices.length, 1);
      expect(s.currentDevices.single.name, 'Bob (renamed)');
      expect(s.currentDevices.single.ip, '192.168.1.9');
    });

    test('own broadcasts and public IPs are ignored', () {
      final s = make();
      expect(s.ingest(DiscoveryMessage(kind: 'announce', id: _id1, name: 'Me', port: 1), '192.168.1.2'), isFalse);
      expect(s.ingest(DiscoveryMessage(kind: 'announce', id: _id2, name: 'Evil', port: 1), '8.8.8.8'), isFalse);
      expect(s.currentDevices, isEmpty);
    });

    test('devices go offline after the timeout', () {
      var now = DateTime(2026, 1, 1, 12);
      final s = DiscoveryService(
          selfId: _id1, localName: () => 'Me', localPort: () => 1, clock: () => now);
      s.ingest(DiscoveryMessage(kind: 'announce', id: _id2, name: 'Bob', port: 1), '10.0.0.2');
      final d = s.currentDevices.single;
      expect(d.isOnline(now, const Duration(seconds: 20)), isTrue);
      now = now.add(const Duration(seconds: 30));
      expect(d.isOnline(now, const Duration(seconds: 20)), isFalse);
    });
  });

  group('Settings (MVVM wiring)', () {
    test('first launch loads defaults when nothing is saved', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await (await SettingsService.create()).load();
      expect(settings.deviceName, isNotEmpty);
      expect(settings.port, AppConstants.defaultPort);
      expect(settings.themeMode, ThemeMode.system);
    });

    test('an out-of-range saved theme falls back to the default', () async {
      SharedPreferences.setMockInitialValues({'themeMode': 99});
      final settings = await (await SettingsService.create()).load();
      expect(settings.themeMode, ThemeMode.system);
    });

    test('validation rules', () {
      expect(SettingsViewModel.validatePort('52525'), isNull);
      expect(SettingsViewModel.validatePort('80'), isNotNull);
      expect(SettingsViewModel.validatePort('abc'), isNotNull);
      expect(SettingsViewModel.validateDeviceName('  '), isNotNull);
      expect(SettingsViewModel.validateConcurrent('0'), isNotNull);
      expect(SettingsViewModel.validateMaxFileSizeMb('1024'), isNull);
      expect(SettingsViewModel.validateChunkSizeKb('1'), isNotNull);
    });

    test('invalid rejected, valid saved and reloaded', () async {
      SharedPreferences.setMockInitialValues({});
      final service = await SettingsService.create();
      const initial = AppSettings(
        deviceName: 'PC', port: 52525, downloadDir: '/tmp', themeMode: ThemeMode.system,
        launchAtStartup: false, maxConcurrentTransfers: 3, maxFileSizeMb: 100,
        discoveryEnabled: true, notificationsEnabled: true,
      );
      final vm = SettingsViewModel(service, initial);
      expect(await vm.save(initial.copyWith(port: 5)), isNotNull);
      expect(vm.settings.port, 52525);
      expect(await vm.save(initial.copyWith(deviceName: 'Front Desk', port: 60000, autoAcceptTrusted: true)), isNull);
      final reloaded = await (await SettingsService.create()).load();
      expect(reloaded.deviceName, 'Front Desk');
      expect(reloaded.port, 60000);
      expect(reloaded.autoAcceptTrusted, isTrue);
    });
  });
}
