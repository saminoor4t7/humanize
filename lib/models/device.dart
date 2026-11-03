/// MODEL: a computer discovered on the LAN (or added manually).
class Device {
  const Device({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.lastSeen,
    this.isManual = false,
  });

  /// SHA-256 of the peer's public key (64 hex chars). Claimed by discovery,
  /// but only PROVEN during the signed handshake when connecting.
  final String id;
  final String name;
  final String ip;
  final int port;
  final DateTime lastSeen;
  final bool isManual;

  bool isOnline(DateTime now, Duration timeout) =>
      now.difference(lastSeen) <= timeout;

  Device copyWith({String? name, String? ip, int? port, DateTime? lastSeen, bool? isManual}) {
    return Device(
      id: id,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      lastSeen: lastSeen ?? this.lastSeen,
      isManual: isManual ?? this.isManual,
    );
  }
}
