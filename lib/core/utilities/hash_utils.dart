import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../errors/app_exceptions.dart';

/// Incremental SHA-256 (never needs the whole file in memory).
class Sha256Accumulator {
  Sha256Accumulator() : _out = _DigestSink() {
    _sink = sha256.startChunkedConversion(_out);
  }

  final _DigestSink _out;
  late final ByteConversionSink _sink;
  bool _closed = false;

  void add(List<int> data) => _sink.add(data);

  /// Finishes the hash and returns lowercase hex. Can be called once.
  String closeHex() {
    if (!_closed) {
      _sink.close();
      _closed = true;
    }
    return _out.value.toString();
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

/// Result of hashing the first N bytes of a file.
class PrefixHash {
  PrefixHash(this.prefixHex, this.running);

  /// SHA-256 of exactly the prefix bytes (for comparing with the peer).
  final String prefixHex;

  /// Still-open accumulator that has already consumed the prefix, so the rest
  /// of the file can be appended and the FULL-file hash produced at the end.
  final Sha256Accumulator running;
}

/// Reads [length] bytes from the start of [file] once, feeding two
/// accumulators: one closed immediately (the prefix digest) and one kept open.
Future<PrefixHash> hashPrefix(File file, int length, {int chunkSize = 1 << 20}) async {
  final prefix = Sha256Accumulator();
  final running = Sha256Accumulator();
  if (length > 0) {
    final raf = await file.open();
    try {
      var remaining = length;
      while (remaining > 0) {
        final data = await raf.read(min(chunkSize, remaining));
        if (data.isEmpty) {
          throw const IntegrityException('File is shorter than expected.');
        }
        prefix.add(data);
        running.add(data);
        remaining -= data.length;
      }
    } finally {
      await raf.close();
    }
  }
  return PrefixHash(prefix.closeHex(), running);
}
