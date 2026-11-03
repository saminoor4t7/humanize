import 'dart:io';

/// Real network facts about this machine. Also the gatekeeper that keeps
/// Humanize on private networks: it never talks to public IP addresses.
class NetworkInfo {
  NetworkInfo._();

  /// First private LAN IPv4 address of an up interface, or null if offline.
  static Future<String?> findLocalIPv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (isPrivateIPv4(addr.address)) return addr.address;
        }
      }
    } on SocketException {
      return null;
    }
    return null;
  }

  /// All private IPv4 addresses (used to compute broadcast targets).
  static Future<List<String>> localPrivateIPv4s() async {
    final result = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (isPrivateIPv4(addr.address)) result.add(addr.address);
        }
      }
    } on SocketException {
      // Offline: no addresses.
    }
    return result;
  }

  static List<int>? _parse(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    final nums = <int>[];
    for (final part in parts) {
      final n = int.tryParse(part);
      if (n == null || n < 0 || n > 255 || part.length > 3) return null;
      nums.add(n);
    }
    return nums;
  }

  static bool isValidIPv4(String ip) => _parse(ip) != null;

  /// RFC 1918 private ranges: 10/8, 172.16/12, 192.168/16.
  static bool isPrivateIPv4(String ip) {
    final n = _parse(ip);
    if (n == null) return false;
    return n[0] == 10 ||
        (n[0] == 172 && n[1] >= 16 && n[1] <= 31) ||
        (n[0] == 192 && n[1] == 168);
  }

  /// Private, loopback (127/8) or link-local (169.254/16): "this is not the internet".
  static bool isPrivateOrLoopbackIPv4(String ip) {
    final n = _parse(ip);
    if (n == null) return false;
    return isPrivateIPv4(ip) ||
        n[0] == 127 ||
        (n[0] == 169 && n[1] == 254);
  }
}
