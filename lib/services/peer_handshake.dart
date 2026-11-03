import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../core/constants/protocol_constants.dart';
import '../core/errors/app_exceptions.dart';
import '../core/utilities/fingerprint.dart';
import 'security_service.dart';
import 'transfer_protocol.dart';

/// Who is on the other end of an authenticated connection.
class PeerInfo {
  const PeerInfo({
    required this.id,
    required this.name,
    required this.publicKeyPem,
    required this.ip,
    this.listenPort,
  });

  final String id;
  final String name;
  final String publicKeyPem;
  final String ip;
  final int? listenPort;
}

/// Mutual authentication that runs inside the TLS tunnel:
///
///   C -> S  HELLO     {v, id, name, port, publicKeyPem, nonceC}
///   S -> C  CHALLENGE {v, id, name, publicKeyPem, nonceS, sig_S}
///   C -> S  AUTH      {sig_C}
///   S -> C  AUTH_OK
///
/// sig_S signs ("server", nonceC, nonceS, serverTlsFp) and sig_C signs
/// ("client", nonceC, nonceS, serverTlsFp). Each side recomputes the message
/// itself, using the TLS certificate it actually saw, so a relay with a
/// different certificate cannot make both signatures verify.
class PeerHandshake {
  PeerHandshake._();

  static final Random _rng = Random.secure();

  static Uint8List _nonce() =>
      Uint8List.fromList(List<int>.generate(32, (_) => _rng.nextInt(256)));

  static String _cleanName(Object? raw) {
    final s = (raw is String ? raw : '').replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
    if (s.isEmpty) return 'Unknown device';
    return s.length > 64 ? s.substring(0, 64) : s;
  }

  static Uint8List _b64(Object? v, {int? exactLength}) {
    if (v is! String || v.length > 4096) {
      throw const AuthException('Malformed authentication data.');
    }
    try {
      final bytes = base64.decode(v);
      if (exactLength != null && bytes.length != exactLength) {
        throw const AuthException('Malformed authentication data.');
      }
      return bytes;
    } on FormatException {
      throw const AuthException('Malformed authentication data.');
    }
  }

  static String _pubKey(Map<String, dynamic> m, String expectedId) {
    final pem = m['publicKeyPem'];
    final id = m['id'];
    if (pem is! String || id is! String || pem.length > 4096) {
      throw const AuthException('Missing identity information.');
    }
    if (!Fingerprint.isValid(id)) {
      throw const AuthException('Invalid device ID.');
    }
    // The ID must be the hash of the key it came with: it cannot be forged.
    late final String computed;
    try {
      computed = Fingerprint.ofPem(pem);
    } on FormatException {
      throw const AuthException('Invalid public key.');
    }
    if (computed != id) {
      throw const AuthException('Device ID does not match its public key.');
    }
    return pem;
  }

  static void _checkVersion(Map<String, dynamic> m) {
    if (m['v'] != ProtocolConstants.version) {
      throw ProtocolException(
          'Incompatible Humanize version (peer uses protocol ${m['v']}, this app uses ${ProtocolConstants.version}).');
    }
  }

  /// Client side. [serverTlsFingerprint] is the SHA-256 of the certificate the
  /// TLS layer actually received. If [expectedPeerId] is given and the server
  /// proves a different identity, the connection is refused.
  static Future<PeerInfo> asClient({
    required FrameReader reader,
    required FrameWriter writer,
    required SecurityService security,
    required String localName,
    required int localPort,
    required Uint8List serverTlsFingerprint,
    required String remoteIp,
    String? expectedPeerId,
  }) async {
    final nonceC = _nonce();
    await writer.writeJson(ProtocolConstants.hello, {
      'v': ProtocolConstants.version,
      'id': security.identity.id,
      'name': localName,
      'port': localPort,
      'publicKeyPem': security.identity.publicKeyPem,
      'nonce': base64.encode(nonceC),
    });

    final frame = await reader.next(timeout: ProtocolConstants.handshakeTimeout);
    if (frame.type == ProtocolConstants.error) {
      throw AuthException(_cleanName(frame.json()['message']));
    }
    if (frame.type != ProtocolConstants.challenge) {
      throw const ProtocolException('Unexpected reply during handshake.');
    }
    final m = frame.json();
    _checkVersion(m);
    final serverId = m['id'] as String? ?? '';
    final serverPem = _pubKey(m, serverId);
    final nonceS = _b64(m['nonce'], exactLength: 32);
    final sigS = _b64(m['signature']);

    final serverMessage = SecurityService.authMessage(
      role: 'server',
      clientNonce: nonceC,
      serverNonce: nonceS,
      serverTlsFingerprint: serverTlsFingerprint,
    );
    if (!SecurityService.verify(serverPem, serverMessage, sigS)) {
      throw const AuthException(
          'Could not verify the other computer. The connection may be intercepted.');
    }
    if (expectedPeerId != null && expectedPeerId != serverId) {
      throw const AuthException(
          'The computer at this address is not the device you selected (identity changed).');
    }

    final clientMessage = SecurityService.authMessage(
      role: 'client',
      clientNonce: nonceC,
      serverNonce: nonceS,
      serverTlsFingerprint: serverTlsFingerprint,
    );
    await writer.writeJson(ProtocolConstants.auth, {
      'signature': base64.encode(security.sign(clientMessage)),
    });

    final ok = await reader.next(timeout: ProtocolConstants.handshakeTimeout);
    if (ok.type == ProtocolConstants.error) {
      throw AuthException(_cleanName(ok.json()['message']));
    }
    if (ok.type != ProtocolConstants.authOk) {
      throw const ProtocolException('Handshake was not confirmed.');
    }
    return PeerInfo(
      id: serverId,
      name: _cleanName(m['name']),
      publicKeyPem: serverPem,
      ip: remoteIp,
    );
  }

  /// Server side.
  static Future<PeerInfo> asServer({
    required FrameReader reader,
    required FrameWriter writer,
    required SecurityService security,
    required String localName,
    required String remoteIp,
  }) async {
    try {
      final hello = await reader.next(timeout: ProtocolConstants.handshakeTimeout);
      if (hello.type != ProtocolConstants.hello) {
        throw const ProtocolException('Expected a hello message.');
      }
      final m = hello.json();
      _checkVersion(m);
      final clientId = m['id'] as String? ?? '';
      final clientPem = _pubKey(m, clientId);
      final nonceC = _nonce32(m['nonce']);
      final nonceS = _nonce();
      final tlsFp = security.identity.certFingerprintBytes;

      final serverSig = security.sign(SecurityService.authMessage(
        role: 'server',
        clientNonce: nonceC,
        serverNonce: nonceS,
        serverTlsFingerprint: tlsFp,
      ));
      await writer.writeJson(ProtocolConstants.challenge, {
        'v': ProtocolConstants.version,
        'id': security.identity.id,
        'name': localName,
        'publicKeyPem': security.identity.publicKeyPem,
        'nonce': base64.encode(nonceS),
        'signature': base64.encode(serverSig),
      });

      final authFrame = await reader.next(timeout: ProtocolConstants.handshakeTimeout);
      if (authFrame.type != ProtocolConstants.auth) {
        throw const ProtocolException('Expected an authentication message.');
      }
      final sigC = _b64(authFrame.json()['signature']);
      final ok = SecurityService.verify(
        clientPem,
        SecurityService.authMessage(
          role: 'client',
          clientNonce: nonceC,
          serverNonce: nonceS,
          serverTlsFingerprint: tlsFp,
        ),
        sigC,
      );
      if (!ok) throw const AuthException('Peer authentication failed.');

      await writer.writeJson(ProtocolConstants.authOk, {});
      final port = m['port'];
      return PeerInfo(
        id: clientId,
        name: _cleanName(m['name']),
        publicKeyPem: clientPem,
        ip: remoteIp,
        listenPort: port is int && port > 0 && port <= 65535 ? port : null,
      );
    } on HumanizeException catch (e) {
      // Tell the peer why (best effort), then let the caller close.
      try {
        await writer.writeJson(ProtocolConstants.error, {
          'code': 'auth',
          'message': e.message,
        });
      } catch (_) {}
      rethrow;
    }
  }

  static Uint8List _nonce32(Object? v) => _b64(v, exactLength: 32);
}
