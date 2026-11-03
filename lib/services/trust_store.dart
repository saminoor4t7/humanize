import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A device the user explicitly trusted.
class TrustedDevice {
  const TrustedDevice({required this.id, required this.name, required this.addedAt});

  final String id;
  final String name;
  final DateTime addedAt;

  Map<String, Object?> toJson() =>
      {'id': id, 'name': name, 'addedAt': addedAt.toIso8601String()};

  static TrustedDevice? tryFromJson(String raw) {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return TrustedDevice(
        id: m['id'] as String,
        name: m['name'] as String,
        addedAt: DateTime.parse(m['addedAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

/// SERVICE: persisted trust decisions. Trust is keyed by cryptographic device
/// ID, so renaming a computer or changing its IP never changes who is trusted.
class TrustStore {
  TrustStore(this._prefs) {
    for (final raw in _prefs.getStringList(_key) ?? const <String>[]) {
      final d = TrustedDevice.tryFromJson(raw);
      if (d != null) _devices[d.id] = d;
    }
  }

  static const _key = 'trustedDevices';

  final SharedPreferences _prefs;
  final Map<String, TrustedDevice> _devices = {};
  final StreamController<void> _changes = StreamController<void>.broadcast();

  Stream<void> get changes => _changes.stream;

  List<TrustedDevice> get devices {
    final list = _devices.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  bool isTrusted(String id) => _devices.containsKey(id);

  Future<void> trust(String id, String name) async {
    _devices[id] = TrustedDevice(id: id, name: name, addedAt: DateTime.now());
    await _save();
  }

  Future<void> remove(String id) async {
    if (_devices.remove(id) != null) await _save();
  }

  Future<void> _save() async {
    await _prefs.setStringList(
        _key, _devices.values.map((d) => jsonEncode(d.toJson())).toList());
    _changes.add(null);
  }

  Future<void> dispose() => _changes.close();
}
