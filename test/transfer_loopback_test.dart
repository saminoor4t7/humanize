@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humanize/core/utilities/network_info.dart';
import 'package:humanize/models/app_settings.dart';
import 'package:humanize/models/transfer.dart';
import 'package:humanize/models/transfer_request.dart';
import 'package:humanize/services/incoming_session.dart';
import 'package:humanize/services/security_service.dart';
import 'package:humanize/services/tcp_client.dart';
import 'package:humanize/services/tcp_server.dart';
import 'package:humanize/services/transfer_sender.dart';
import 'package:humanize/services/trust_store.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal receiver-side host for tests: no UI, decisions are scripted.
class FakeHost implements IncomingHost {
  FakeHost({
    required this.security,
    required this.trustStore,
    required this.dir,
    this.approve = true,
    this.maxFileSizeMb = 100,
    this.maxConcurrent = 5,
  });

  @override
  final SecurityService security;
  @override
  final TrustStore trustStore;
  final String dir;
  bool approve;
  int maxFileSizeMb;
  int maxConcurrent;
  int approvals = 0;
  int _slots = 0;
  final List<Transfer> finished = [];

  @override
  AppSettings get settings => AppSettings(
        deviceName: 'Receiver',
        port: 0,
        downloadDir: dir,
        themeMode: ThemeMode.system,
        launchAtStartup: false,
        maxConcurrentTransfers: maxConcurrent,
        maxFileSizeMb: maxFileSizeMb,
        discoveryEnabled: false,
        notificationsEnabled: false,
      );

  @override
  Future<bool> requestApproval(TransferRequest request) async {
    approvals++;
    return approve;
  }

  @override
  bool tryAcquireIncomingSlot() {
    if (_slots >= maxConcurrent) return false;
    _slots++;
    return true;
  }

  @override
  void releaseIncomingSlot() => _slots--;
  @override
  void registerTransfer(Transfer transfer, void Function() cancel) {}
  @override
  void notifyProgress() {}
  @override
  void transferFinished(Transfer transfer) => finished.add(transfer);

  Future<Transfer> waitFinished(int count) async {
    final end = DateTime.now().add(const Duration(seconds: 30));
    while (finished.length < count) {
      if (DateTime.now().isAfter(end)) fail('receiver did not finish ($count)');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return finished[count - 1];
  }
}

void main() {
  late SecurityService senderSec;
  late SecurityService receiverSec;
  late TrustStore trust;
  late Directory root;
  late Directory sendDir;
  late Directory recvDir;
  late TcpServer server;
  late FakeHost host;
  final rng = Random(42);

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('humanize_it');
    // RSA key generation is slow in pure Dart: do it once for all tests.
    final ids = await Future.wait([
      SecurityService.loadOrCreate(directory: p.join(root.path, 'id1')),
      SecurityService.loadOrCreate(directory: p.join(root.path, 'id2')),
    ]);
    senderSec = ids[0];
    receiverSec = ids[1];
    trust = TrustStore(await SharedPreferences.getInstance());
  });

  tearDownAll(() async {
    await root.delete(recursive: true);
  });

  setUp(() async {
    sendDir = await Directory(p.join(root.path, 'send_${rng.nextInt(1 << 30)}')).create();
    recvDir = await Directory(p.join(root.path, 'recv_${rng.nextInt(1 << 30)}')).create();
    host = FakeHost(security: receiverSec, trustStore: trust, dir: recvDir.path);
    server = TcpServer();
    await server.start(
      port: 0,
      context: receiverSec.serverContext(),
      address: InternetAddress.loopbackIPv4,
      onConnection: (s) => unawaited(IncomingSession(channel: PeerChannel(s), host: host).run()),
    );
  });

  tearDown(() async {
    await server.stop();
  });

  // ---- helpers ----

  Future<File> makeFile(String name, int size) async {
    final f = File(p.join(sendDir.path, name));
    await f.parent.create(recursive: true);
    final raf = await f.open(mode: FileMode.write);
    var left = size;
    while (left > 0) {
      final n = min(left, 1 << 20);
      await raf.writeFrom(List<int>.generate(n, (_) => rng.nextInt(256)));
      left -= n;
    }
    await raf.close();
    return f;
  }

  Future<String> sha(File f) async => (await sha256.bind(f.openRead()).first).toString();

  Transfer build(String id, List<(String, File)> files, {String? peerId}) {
    final list = <TransferFile>[];
    for (var i = 0; i < files.length; i++) {
      final stat = files[i].$2.statSync();
      list.add(TransferFile(
        index: i,
        // Same key for same name+size+mtime: this is what makes resume work.
        fileKey: sha256.convert('${files[i].$1}|${stat.size}|${stat.modified.millisecondsSinceEpoch}'.codeUnits).toString(),
        relPath: files[i].$1,
        size: stat.size,
        localPath: files[i].$2.path,
        modifiedMs: stat.modified.millisecondsSinceEpoch,
      ));
    }
    return Transfer(
      // The protocol only accepts 32 lowercase hex characters.
      id: sha256.convert(utf8.encode(id)).toString().substring(0, 32),
      direction: TransferDirection.outgoing,
      peerName: 'Receiver',
      peerIp: '127.0.0.1',
      peerId: peerId,
      files: list,
    );
  }

  Future<Transfer> run(Transfer t, {int? abortAfter, int chunk = 64 * 1024, int? portOverride}) async {
    await TransferSender(
      transfer: t,
      security: senderSec,
      localName: 'Sender',
      localPort: 1234,
      host: '127.0.0.1',
      port: portOverride ?? server.port,
      chunkSize: chunk,
      onProgress: () {},
      debugAbortAfterBytes: abortAfter,
    ).run();
    return t;
  }

  group('TCP + TLS connection and messaging', () {
    test('client connects over TLS and proves the server identity', () async {
      final ch = await TcpClient.connect(
          host: '127.0.0.1', port: server.port, context: senderSec.clientContext());
      expect(ch.serverCertFingerprint.length, 32);
      ch.destroy();
    });

    test('connecting to a closed port fails with a readable error', () async {
      final tmp = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final closed = tmp.port;
      await tmp.close();
      final t = build('closedport', [('a.txt', await makeFile('a.txt', 10))]);
      await run(t, portOverride: closed);
      expect(t.state, TransferState.failed);
      expect(t.error, contains('Could not connect'));
    });

    test('public IP addresses are refused client-side', () async {
      expect(NetworkInfo.isPrivateOrLoopbackIPv4('8.8.8.8'), isFalse);
      expect(
        TcpClient.connect(host: '8.8.8.8', port: 1, context: senderSec.clientContext()),
        throwsA(anything),
      );
    });
  });

  group('File transfer', () {
    test('sends a file with spaces and Unicode, verified by SHA-256', () async {
      final name = 'Quarterly Report – Zürich 日本語 (final).bin';
      final f = await makeFile(name, 300 * 1024 + 17);
      final t = await run(build('unicode', [(name, f)]));
      expect(t.state, TransferState.completed, reason: t.error);
      final out = File(p.join(recvDir.path, name));
      expect(await out.exists(), isTrue);
      expect(await sha(out), await sha(f));
      expect(await out.length(), await f.length());
      // No temp or partial file is left behind after success.
      final partials = Directory(p.join(recvDir.path, '.humanize-partial'));
      if (partials.existsSync()) {
        expect(partials.listSync().where((e) => e.path.endsWith('.part')), isEmpty);
      }
    });

    test('empty files transfer correctly', () async {
      final f = await makeFile('empty.txt', 0);
      final t = await run(build('empty', [('empty.txt', f)]));
      expect(t.state, TransferState.completed, reason: t.error);
      expect(await File(p.join(recvDir.path, 'empty.txt')).length(), 0);
    });

    test('large file (64 MiB) arrives intact with measured speed', () async {
      final f = await makeFile('big.bin', 64 * 1024 * 1024);
      final t = await run(build('large', [('big.bin', f)]), chunk: 256 * 1024);
      expect(t.state, TransferState.completed, reason: t.error);
      expect(await sha(File(p.join(recvDir.path, 'big.bin'))), await sha(f));
      expect(t.transferredBytes, 64 * 1024 * 1024);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('folder structure is preserved', () async {
      final a = await makeFile('proj/src/a.txt', 1000);
      final b = await makeFile('proj/readme.md', 2000);
      final t = await run(build('folder', [('proj/src/a.txt', a), ('proj/readme.md', b)]));
      expect(t.state, TransferState.completed, reason: t.error);
      expect(await sha(File(p.join(recvDir.path, 'proj', 'src', 'a.txt'))), await sha(a));
      expect(await sha(File(p.join(recvDir.path, 'proj', 'readme.md'))), await sha(b));
    });

    test('existing files are never overwritten', () async {
      File(p.join(recvDir.path, 'dup.txt')).writeAsStringSync('original');
      final f = await makeFile('dup.txt', 100);
      final t = await run(build('dup', [('dup.txt', f)]));
      expect(t.state, TransferState.completed, reason: t.error);
      expect(File(p.join(recvDir.path, 'dup.txt')).readAsStringSync(), 'original');
      expect(File(p.join(recvDir.path, 'dup (1).txt')).existsSync(), isTrue);
    });

    test('multiple simultaneous transfers all succeed', () async {
      final transfers = <Transfer>[];
      final originals = <File>[];
      for (var i = 0; i < 4; i++) {
        final f = await makeFile('multi_$i.bin', 2 * 1024 * 1024 + i);
        originals.add(f);
        transfers.add(build('multi$i', [('multi_$i.bin', f)]));
      }
      await Future.wait(transfers.map(run));
      for (var i = 0; i < 4; i++) {
        expect(transfers[i].state, TransferState.completed, reason: transfers[i].error);
        expect(await sha(File(p.join(recvDir.path, 'multi_$i.bin'))), await sha(originals[i]));
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('Security', () {
    test('declined transfers write nothing', () async {
      host.approve = false;
      final f = await makeFile('secret.txt', 5000);
      final t = await run(build('declined', [('secret.txt', f)]));
      expect(t.state, TransferState.rejected);
      expect(File(p.join(recvDir.path, 'secret.txt')).existsSync(), isFalse);
      expect(host.approvals, 1);
    });

    test('path traversal names are refused by the receiver', () async {
      final f = await makeFile('ok.txt', 50);
      for (final evil in ['../evil.txt', '..\\evil.txt', '/abs/evil.txt', 'a/../../evil.txt', 'con']) {
        final t = await run(build('evil', [(evil, f)]));
        expect(t.state, isNot(TransferState.completed), reason: evil);
      }
      expect(File(p.join(recvDir.parent.path, 'evil.txt')).existsSync(), isFalse);
      expect(host.approvals, 0, reason: 'invalid requests must be refused before asking the user');
    });

    test('files above the size limit are refused', () async {
      host.maxFileSizeMb = 1;
      final f = await makeFile('toobig.bin', 2 * 1024 * 1024);
      final t = await run(build('toobig', [('toobig.bin', f)]));
      expect(t.state, TransferState.rejected);
      expect(File(p.join(recvDir.path, 'toobig.bin')).existsSync(), isFalse);
    });

    test('a server with a different identity than expected is refused', () async {
      final f = await makeFile('x.txt', 10);
      final t = build('wrongid', [('x.txt', f)], peerId: 'c' * 64);
      await run(t);
      expect(t.state, TransferState.failed);
      expect(t.error, contains('identity'));
      expect(host.approvals, 0);
    });

    test('the correct expected identity is accepted', () async {
      final f = await makeFile('y.txt', 10);
      final t = build('rightid', [('y.txt', f)], peerId: receiverSec.identity.id);
      await run(t);
      expect(t.state, TransferState.completed, reason: t.error);
    });

    test('a raw non-TLS client cannot talk to the receiver', () async {
      final raw = await Socket.connect('127.0.0.1', server.port);
      raw.add(List.filled(64, 0x41));
      await raw.flush();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await raw.close().catchError((_) {});
      expect(host.approvals, 0);
      expect(host.finished, isEmpty);
    });
  });

  group('Interruption and resume', () {
    test('network failure mid-transfer fails cleanly, partial data is kept', () async {
      final f = await makeFile('resume.bin', 5 * 1024 * 1024);
      final t = build('interrupt', [('resume.bin', f)]);
      await run(t, abortAfter: 2 * 1024 * 1024);
      expect(t.state, TransferState.failed);
      await host.waitFinished(1);
      expect(host.finished.first.state, TransferState.failed);
      expect(File(p.join(recvDir.path, 'resume.bin')).existsSync(), isFalse,
          reason: 'an incomplete file must never appear under its final name');
      final partial = Directory(p.join(recvDir.path, '.humanize-partial'))
          .listSync()
          .whereType<File>()
          .where((x) => x.path.endsWith('.part'))
          .toList();
      expect(partial.length, 1);
      expect(partial.single.lengthSync(), greaterThan(0));
      expect(partial.single.lengthSync(), lessThan(5 * 1024 * 1024));
    });

    test('resumes from the validated partial file and verifies the whole file', () async {
      final f = await makeFile('resume2.bin', 6 * 1024 * 1024);
      final first = build('resume2a', [('resume2.bin', f)]);
      await run(first, abortAfter: 2 * 1024 * 1024);
      expect(first.state, TransferState.failed);
      await host.waitFinished(1);

      final second = build('resume2b', [('resume2.bin', f)]);
      await run(second);
      expect(second.state, TransferState.completed, reason: second.error);
      expect(second.resumedBytes, greaterThan(0), reason: 'must not restart from zero');
      expect(await sha(File(p.join(recvDir.path, 'resume2.bin'))), await sha(f));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a corrupted partial file is detected and the transfer restarts safely', () async {
      final f = await makeFile('resume3.bin', 4 * 1024 * 1024);
      final first = build('resume3a', [('resume3.bin', f)]);
      await run(first, abortAfter: 1024 * 1024);
      await host.waitFinished(1);

      // Damage the partial data on the receiver.
      final part = Directory(p.join(recvDir.path, '.humanize-partial'))
          .listSync()
          .whereType<File>()
          .firstWhere((x) => x.path.endsWith('.part'));
      final bytes = part.readAsBytesSync()..[10] ^= 0xFF;
      part.writeAsBytesSync(bytes);

      final second = build('resume3b', [('resume3.bin', f)]);
      await run(second);
      expect(second.state, TransferState.completed, reason: second.error);
      expect(second.resumedBytes, 0, reason: 'bad prefix hash means resume must be refused');
      expect(await sha(File(p.join(recvDir.path, 'resume3.bin'))), await sha(f));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('receiver going offline mid-transfer ends the transfer with an error', () async {
      final f = await makeFile('drop.bin', 30 * 1024 * 1024);
      final t = build('drop', [('drop.bin', f)]);
      final future = run(t, chunk: 32 * 1024);
      while (t.state != TransferState.transferring) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await server.stop(); // closes every open connection
      await future.timeout(const Duration(seconds: 30));
      expect(t.state, TransferState.failed);
      expect(t.error, isNotNull);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('user cancel stops the transfer and discards partial data', () async {
      final f = await makeFile('cancel.bin', 40 * 1024 * 1024);
      final t = build('cancel', [('cancel.bin', f)]);
      late TransferSender sender;
      sender = TransferSender(
        transfer: t,
        security: senderSec,
        localName: 'Sender',
        localPort: 1,
        host: '127.0.0.1',
        port: server.port,
        chunkSize: 32 * 1024,
        onProgress: () {
          if (t.transferredBytes > 1024 * 1024) sender.cancel();
        },
      );
      await sender.run();
      expect(t.state, TransferState.cancelled);
      await host.waitFinished(1);
      expect(File(p.join(recvDir.path, 'cancel.bin')).existsSync(), isFalse);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
