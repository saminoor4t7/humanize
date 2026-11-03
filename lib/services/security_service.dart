import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/utilities/file_utils.dart';
import '../core/utilities/fingerprint.dart';

/// This computer's long-term identity.
///
/// * RSA key pair, generated once and stored in the app-support folder.
/// * Device ID = SHA-256 of the public key (what peers trust/pin).
/// * A self-signed X.509 certificate of the same key pair, used only so that
///   TLS can encrypt the connection.
class DeviceIdentity {
  const DeviceIdentity({
    required this.certPem,
    required this.privateKeyPem,
    required this.publicKeyPem,
  });

  final String certPem;
  final String privateKeyPem;
  final String publicKeyPem;

  String get id => Fingerprint.ofPem(publicKeyPem);

  /// SHA-256 of the TLS certificate (DER). Bound into the signed handshake.
  Uint8List get certFingerprintBytes =>
      Uint8List.fromList(sha256.convert(PemUtils.toDer(certPem)).bytes);
}

/// SERVICE: identity, TLS contexts and handshake signatures.
///
/// Security model
/// --------------
/// 1. TLS (1.2/1.3) encrypts and integrity-protects every byte.
/// 2. We do NOT rely on certificate authorities. Instead, after TLS is up,
///    both sides run a signed challenge (see PeerHandshake): each proves it
///    owns the private key behind its claimed device ID, and the signature
///    covers the server's TLS certificate fingerprint. A man-in-the-middle
///    using a different TLS certificate therefore breaks the signature.
/// 3. Knowing a device ID is not trust. Trust is an explicit user decision
///    stored in [TrustStore]; unknown devices always need per-transfer approval.
class SecurityService {
  SecurityService._(this.identity)
      : _privateKey = CryptoUtils.rsaPrivateKeyFromPem(identity.privateKeyPem);

  final DeviceIdentity identity;
  final RSAPrivateKey _privateKey;

  /// Minimum accepted RSA modulus size for peer keys.
  static const int minPeerKeyBits = 2048;

  static Future<SecurityService> loadOrCreate({String? directory, int keySize = 2048}) async {
    final dirPath = directory ??
        p.join((await getApplicationSupportDirectory()).path, 'identity');
    final file = File(p.join(dirPath, 'identity.json'));
    if (await file.exists()) {
      try {
        final m = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        return SecurityService._(DeviceIdentity(
          certPem: m['certPem'] as String,
          privateKeyPem: m['privateKeyPem'] as String,
          publicKeyPem: m['publicKeyPem'] as String,
        ));
      } catch (_) {
        // Corrupt identity file: generate a new identity below.
      }
    }
    final identity = await generateIdentity(keySize: keySize);
    await FileUtils.atomicWrite(
      file,
      jsonEncode({
        'certPem': identity.certPem,
        'privateKeyPem': identity.privateKeyPem,
        'publicKeyPem': identity.publicKeyPem,
      }),
    );
    return SecurityService._(identity);
  }

  /// RSA key generation in pure Dart takes seconds, so it runs in an isolate.
  static Future<DeviceIdentity> generateIdentity({int keySize = 2048}) {
    return Isolate.run(() {
      final pair = CryptoUtils.generateRSAKeyPair(keySize: keySize);
      final priv = pair.privateKey as RSAPrivateKey;
      final pub = pair.publicKey as RSAPublicKey;
      final csr = X509Utils.generateRsaCsrPem(
        {'CN': 'Humanize Device', 'O': 'Humanize'},
        priv,
        pub,
      );
      final cert = X509Utils.generateSelfSignedCertificate(priv, csr, 3650);
      return DeviceIdentity(
        certPem: cert,
        privateKeyPem: CryptoUtils.encodeRSAPrivateKeyToPem(priv),
        publicKeyPem: CryptoUtils.encodeRSAPublicKeyToPem(pub),
      );
    });
  }

  /// Server side: presents our certificate. Clients are authenticated by the
  /// signed handshake, not by TLS client certificates.
  SecurityContext serverContext() {
    final ctx = SecurityContext(withTrustedRoots: false);
    ctx.useCertificateChainBytes(utf8.encode(identity.certPem));
    ctx.usePrivateKeyBytes(utf8.encode(identity.privateKeyPem));
    return ctx;
  }

  /// Client side: no system roots. The handshake decides who we are talking to.
  SecurityContext clientContext() => SecurityContext(withTrustedRoots: false);

  // ---- Handshake signatures ----

  /// The exact bytes both sides sign. Binds role + both nonces + the server's
  /// TLS certificate so signatures cannot be replayed or relayed.
  static Uint8List authMessage({
    required String role,
    required Uint8List clientNonce,
    required Uint8List serverNonce,
    required Uint8List serverTlsFingerprint,
  }) {
    final b = BytesBuilder()
      ..add(utf8.encode('humanize-auth-v1|$role|'))
      ..add(clientNonce)
      ..add(serverNonce)
      ..add(serverTlsFingerprint);
    return b.toBytes();
  }

  Uint8List sign(Uint8List message) => CryptoUtils.rsaSign(_privateKey, message);

  /// Verifies [signature] using a peer-supplied public key PEM. The key is
  /// untrusted input: size-checked and parsed defensively.
  static bool verify(String publicKeyPem, Uint8List message, Uint8List signature) {
    try {
      if (publicKeyPem.length > 4096) return false;
      final key = CryptoUtils.rsaPublicKeyFromPem(publicKeyPem);
      final modulus = key.modulus;
      if (modulus == null || modulus.bitLength < minPeerKeyBits) return false;
      return CryptoUtils.rsaVerify(key, message, signature);
    } catch (_) {
      return false;
    }
  }
}
