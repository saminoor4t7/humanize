import 'dart:async';
import 'dart:io';

import '../core/utilities/network_info.dart';

/// SERVICE: the receiving TLS/TCP listener.
///
/// * Binds on all IPv4 interfaces at the configured port.
/// * Refuses connections from non-private addresses, so even if a firewall
///   rule is too wide the service never talks to the public internet.
/// * Tracks open sockets so [stop] can close everything and release the port.
class TcpServer {
  SecureServerSocket? _server;
  final Set<Socket> _sockets = {};
  int rejectedConnections = 0;

  bool get isRunning => _server != null;

  /// Actual bound port (useful when started with port 0 in tests).
  int get port => _server?.port ?? 0;

  Future<void> start({
    required int port,
    required SecurityContext context,
    required void Function(SecureSocket socket) onConnection,
    void Function(Object error)? onError,
    InternetAddress? address,
  }) async {
    if (_server != null) return;
    final server = await SecureServerSocket.bind(
      address ?? InternetAddress.anyIPv4,
      port,
      context,
    );
    _server = server;
    server.listen(
      (socket) {
        if (!NetworkInfo.isPrivateOrLoopbackIPv4(socket.remoteAddress.address)) {
          rejectedConnections++;
          socket.destroy();
          return;
        }
        try {
          socket.setOption(SocketOption.tcpNoDelay, true);
        } catch (_) {}
        _sockets.add(socket);
        socket.done.then(
          (_) => _sockets.remove(socket),
          onError: (_) => _sockets.remove(socket),
        );
        onConnection(socket);
      },
      // A failed TLS handshake from a scanner/old client must not stop us.
      onError: (Object e) => onError?.call(e),
      cancelOnError: false,
    );
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close();
    for (final s in _sockets.toList()) {
      s.destroy();
    }
    _sockets.clear();
  }
}
