import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:humanize/core/constants/protocol_constants.dart';
import 'package:humanize/core/errors/app_exceptions.dart';
import 'package:humanize/services/transfer_protocol.dart';

Uint8List frameBytes(int type, List<int> payload) {
  final header = ByteData(5)
    ..setUint32(0, payload.length + 1)
    ..setUint8(4, type);
  return Uint8List.fromList([...header.buffer.asUint8List(), ...payload]);
}

Stream<Uint8List> fromPieces(List<List<int>> pieces) async* {
  for (final p in pieces) {
    yield Uint8List.fromList(p);
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('FrameReader (TCP gives no message boundaries)', () {
    test('reads a frame delivered one byte at a time', () async {
      final bytes = frameBytes(ProtocolConstants.chunk, List.generate(300, (i) => i % 251));
      final reader = FrameReader(fromPieces([for (final b in bytes) [b]]));
      final f = await reader.next();
      expect(f.type, ProtocolConstants.chunk);
      expect(f.payload.length, 300);
      expect(f.payload[250], 250);
    });

    test('splits several frames glued into one read', () async {
      final a = frameBytes(ProtocolConstants.hello, utf8.encode('{"a":1}'));
      final b = frameBytes(ProtocolConstants.chunk, [1, 2, 3]);
      final c = frameBytes(ProtocolConstants.sessionDone, const []);
      final reader = FrameReader(fromPieces([[...a, ...b, ...c]]));
      expect((await reader.next()).json()['a'], 1);
      expect((await reader.next()).payload, [1, 2, 3]);
      final last = await reader.next();
      expect(last.type, ProtocolConstants.sessionDone);
      expect(last.payload, isEmpty);
      expect(await reader.readFrame(), isNull); // clean EOF between frames
    });

    test('a frame split mid-header and mid-payload is reassembled', () async {
      final bytes = frameBytes(ProtocolConstants.chunk, List.filled(1000, 7));
      final reader = FrameReader(fromPieces([
        bytes.sublist(0, 2),
        bytes.sublist(2, 6),
        bytes.sublist(6, 500),
        bytes.sublist(500),
      ]));
      final f = await reader.next();
      expect(f.payload.length, 1000);
      expect(f.payload.every((x) => x == 7), isTrue);
    });

    test('EOF in the middle of a frame is an error', () async {
      final bytes = frameBytes(ProtocolConstants.chunk, List.filled(100, 1));
      final reader = FrameReader(fromPieces([bytes.sublist(0, 50)]));
      expect(reader.next(), throwsA(isA<ProtocolException>()));
    });

    test('oversized control frame is rejected before allocation', () async {
      final header = ByteData(5)
        ..setUint32(0, ProtocolConstants.maxControlPayload + 10)
        ..setUint8(4, ProtocolConstants.hello);
      final reader = FrameReader(fromPieces([header.buffer.asUint8List()]));
      expect(reader.next(), throwsA(isA<ProtocolException>()));
    });

    test('zero length frame is rejected', () async {
      final reader = FrameReader(fromPieces([
        [0, 0, 0, 0, 1]
      ]));
      expect(reader.next(), throwsA(isA<ProtocolException>()));
    });

    test('malformed JSON in a control frame raises ProtocolException', () {
      final f = Frame(ProtocolConstants.hello, Uint8List.fromList(utf8.encode('not json')));
      expect(f.json, throwsA(isA<ProtocolException>()));
    });

    test('idle timeout is reported', () async {
      final controller = StreamController<Uint8List>();
      final reader = FrameReader(controller.stream);
      await expectLater(
        reader.next(timeout: const Duration(milliseconds: 100)),
        throwsA(isA<ConnectionTimeoutException>()),
      );
      await controller.close();
    });
  });
}
