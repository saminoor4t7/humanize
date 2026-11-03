import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../core/constants/protocol_constants.dart';
import '../core/errors/app_exceptions.dart';
import '../core/utilities/network_info.dart';
import 'transfer_protocol.dart';

/// An open TLS connection with its frame reader/writer.
class PeerChannel {
  PeerChannel(this.socket)
      : reader = FrameReader(socket),
        writer = FrameWriter(socket);

  final SecureSocket socket;
  final FrameReader reader;
  final FrameWriter writer;

  String get remoteIp => socket.remoteAddress.address;

  /// SHA-256 of the TLS certificate the server presented.
  Uint8List get serverCertFingerprint {
    final cert = socket.peerCertificate;
    if (cert == null) {
      throw const AuthException('The other computer did not present a certificate.');
    }
    return Uint8List.fromList(sha256.convert(cert.der).bytes);
  }

  void destroy() {
    try {
      socket.destroy();
    } catch (_) {}
  }
}

/// SERVICE: outgoing TLS/TCP connections.
class TcpClient {
  TcpClient._();

  /// Connects with a timeout and converts low-level errors into messages a
  /// person can act on.
  ///
  /// `onBadCertificate` returns true because Humanize certificates are
  /// self-signed. That is safe ONLY because the next step, PeerHandshake,
  /// authenticates the peer's identity and binds the signature to the exact
  /// certificate seen here. Never use this client without that handshake.
  static Future<PeerChannel> connect({
    required String host,
    required int port,
    required SecurityContext context,
    Duration timeout = ProtocolConstants.connectTimeout,
  }) async {
    if (!NetworkInfo.isPrivateOrLoopbackIPv4(host)) {
      throw const ConnectionFailedException(
          'Humanize only connects to computers on your local network (private IP addresses).');
    }
    try {
      final socket = await SecureSocket.connect(
        host,
        port,
        context: context,
        timeout: timeout,
        onBadCertificate: (_) => true,
      );
      try {
        socket.setOption(SocketOption.tcpNoDelay, true);
      } catch (_) {}
      return PeerChannel(socket);
    } on TimeoutException {
      throw ConnectionFailedException(
          'Connection to $host:$port timed out. Check that Humanize is running there and the firewall allows it.');
    } on HandshakeException {
      throw ConnectionFailedException(
          '$host:$port is not a compatible Humanize device (secure connection failed).');
    } on TlsException {
      throw ConnectionFailedException(
          'Secure connection to $host:$port failed.');
    } on SocketException catch (e) {
      final detail = e.osError?.message ?? e.message;
      throw ConnectionFailedException('Could not connect to $host:$port ($detail).');
    }
  }
}
