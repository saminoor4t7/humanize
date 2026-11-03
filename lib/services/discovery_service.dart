import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/constants/protocol_constants.dart';
import '../core/utilities/fingerprint.dart';
import '../core/utilities/network_info.dart';
import '../models/device.dart';

/// A validated discovery datagram.
class DiscoveryMessage {
  const DiscoveryMessage({
    required this.kind,
    required this.id,
    required this.name,
    required this.port,
  });

  /// 'announce' (I am here) or 'query' (who is here? please announce).
  final String kind;
  final String id;
  final String name;
  final int port;

  /// Strictly validates untrusted UDP input. Anything unexpected -> null.
  static DiscoveryMessage? parse(List<int> data) {
    if (data.isEmpty || data.length > 1024) return null;
    try {
      final decoded = jsonDecode(utf8.decode(data));
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['app'] != 'humanize') return null;
      if (decoded['v'] != ProtocolConstants.version) return null;
      final kind = decoded['kind'];
      if (kind != 'announce' && kind != 'query') return null;
      final id = decoded['id'];
      if (id is! String || !Fingerprint.isValid(id)) return null;
      final port = decoded['port'];
      if (port is! int || port < 1 || port > 65535) return null;
      final rawName = decoded['name'];
      if (rawName is! String) return null;
      final name = rawName.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '').trim();
      if (name.isEmpty || name.length > 64) return null;
      return DiscoveryMessage(kind: kind as String, id: id, name: name, port: port);
    } catch (_) {
      return null;
    }
  }

  List<int> encode() => utf8.encode(jsonEncode({
        'app': 'humanize',
        'v': ProtocolConstants.version,
        'kind': kind,
        'id': id,
        'name': name,
        'port': port,
      }));
}

/// SERVICE: finds other Humanize computers with UDP broadcast.
///
/// Discovery is a HINT, not trust: any host can send a packet claiming any
/// id/name. The real identity is proven later by the signed TLS handshake,
/// which refuses a device whose proven id differs from the announced one.
class DiscoveryService {
  DiscoveryService({
    required this.selfId,
    required this.localName,
    required this.localPort,
    this.discoveryPort = ProtocolConstants.discoveryPort,
    this.extraTargets = const [],
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final String selfId;
  final String Function() localName;
  final int Function() localPort;
  final int discoveryPort;

  /// Extra unicast targets (host, port). Used by tests and for probing.
  final List<(InternetAddress, int)> extraTargets;
  final DateTime Function() _clock;

  final Map<String, Device> _devices = {};
  final StreamController<List<Device>> _controller =
      StreamController<List<Device>>.broadcast();

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _sub;
  Timer? _announceTimer;
  Timer? _tickTimer;

  bool get isRunning => _socket != null;
  Stream<List<Device>> get devices => _controller.stream;
  List<Device> get currentDevices => _sorted();

  Future<void> start() async {
    if (_socket != null) return;
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
    );
    socket.broadcastEnabled = true;
    _socket = socket;
    _sub = socket.listen(_onEvent);
    _announceTimer = Timer.periodic(
        ProtocolConstants.announceInterval, (_) => _send('announce'));
    // Re-emit so the UI can flip devices to "offline" as time passes.
    _tickTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _prune();
      _emit();
    });
    unawaited(_send('query'));
    unawaited(_send('announce'));
  }

  Future<void> stop() async {
    _announceTimer?.cancel();
    _tickTimer?.cancel();
    _announceTimer = null;
    _tickTimer = null;
    await _sub?.cancel();
    _sub = null;
    _socket?.close();
    _socket = null;
  }

  /// "Refresh": ask everyone to announce themselves again.
  Future<void> refresh() => _send('query');

  /// Remembers a device found by manual IP entry.
  void addManual(Device device) {
    _devices[device.id] = device.copyWith(isManual: true, lastSeen: _clock());
    _emit();
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }

  // ---- sending ----

  Future<void> _send(String kind) async {
    final socket = _socket;
    if (socket == null) return;
    final data = DiscoveryMessage(
      kind: kind,
      id: selfId,
      name: localName(),
      port: localPort(),
    ).encode();

    final targets = <(InternetAddress, int)>[
      (InternetAddress('255.255.255.255'), discoveryPort),
      ...extraTargets,
    ];
    // Directed broadcast per interface (assumes /24, the common LAN size).
    for (final ip in await NetworkInfo.localPrivateIPv4s()) {
      final parts = ip.split('.');
      targets.add((InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'), discoveryPort));
    }
    for (final (addr, port) in targets) {
      try {
        socket.send(data, addr, port);
      } catch (_) {
        // Interface went away or send buffer full: try again next interval.
      }
    }
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final socket = _socket;
    if (socket == null) return;
    Datagram? d;
    while ((d = socket.receive()) != null) {
      final msg = DiscoveryMessage.parse(d!.data);
      if (msg == null) continue;
      final accepted = ingest(msg, d.address.address);
      if (accepted && msg.kind == 'query') {
        // Answer directly to the asker.
        final reply = DiscoveryMessage(
          kind: 'announce',
          id: selfId,
          name: localName(),
          port: localPort(),
        ).encode();
        try {
          socket.send(reply, d.address, d.port);
        } catch (_) {}
      }
    }
  }

  /// Applies a validated message. Returns false if it was ignored.
  /// Public so tests (and later features) can feed messages without a socket.
  bool ingest(DiscoveryMessage msg, String fromIp, {DateTime? now}) {
    if (msg.id == selfId) return false; // our own broadcast
    if (!NetworkInfo.isPrivateOrLoopbackIPv4(fromIp)) return false;
    final existing = _devices[msg.id];
    if (existing == null && _devices.length >= ProtocolConstants.maxDiscoveredDevices) {
      return false; // flood protection
    }
    // One entry per device id: duplicates just refresh the existing entry.
    _devices[msg.id] = Device(
      id: msg.id,
      name: msg.name,
      ip: fromIp,
      port: msg.port,
      lastSeen: now ?? _clock(),
      isManual: existing?.isManual ?? false,
    );
    _emit();
    return true;
  }

  void _prune() {
    final now = _clock();
    _devices.removeWhere((_, d) =>
        !d.isManual && now.difference(d.lastSeen) > ProtocolConstants.deviceForgetAfter);
  }

  List<Device> _sorted() {
    final now = _clock();
    final list = _devices.values.toList()
      ..sort((a, b) {
        final ao = a.isOnline(now, ProtocolConstants.deviceOfflineAfter);
        final bo = b.isOnline(now, ProtocolConstants.deviceOfflineAfter);
        if (ao != bo) return ao ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return list;
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(_sorted());
  }
}
