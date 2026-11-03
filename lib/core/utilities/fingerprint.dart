import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// PEM helpers.
class PemUtils {
  PemUtils._();

  /// Decodes the base64 body of a PEM block into DER bytes.
  static Uint8List toDer(String pem) {
    final body = pem
        .split(RegExp(r'\r?\n'))
        .where((l) => l.isNotEmpty && !l.startsWith('-----'))
        .join();
    return base64.decode(body.replaceAll(RegExp(r'\s'), ''));
  }
}

/// A device identity is the SHA-256 of its RSA public key (hex, 64 chars).
/// It is derived from the key, so it cannot be claimed without the private key.
class Fingerprint {
  Fingerprint._();

  static final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

  static bool isValid(String s) => _hex64.hasMatch(s);

  static String ofBytes(List<int> bytes) => sha256.convert(bytes).toString();

  static String ofPem(String pem) => ofBytes(PemUtils.toDer(pem));

  /// Short human-comparable form: first 16 hex chars as XXXX-XXXX-XXXX-XXXX.
  static String short(String id) {
    if (id.length < 16) return id.toUpperCase();
    final s = id.substring(0, 16).toUpperCase();
    return '${s.substring(0, 4)}-${s.substring(4, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}';
  }
}
