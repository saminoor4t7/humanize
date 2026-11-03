import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/utilities/file_utils.dart';
import '../models/transfer_record.dart';

/// SERVICE: persistent transfer history (metadata only, never file contents).
/// Stored as one JSON file written atomically, capped to the newest entries.
class HistoryService {
  HistoryService._(this._file, this._records);

  static const int maxEntries = 5000;

  final File _file;
  final List<TransferRecord> _records; // newest first
  final StreamController<void> _changes = StreamController<void>.broadcast();
  Future<void> _writeChain = Future.value();

  static Future<HistoryService> open({String? directory}) async {
    final dir = directory ?? (await getApplicationSupportDirectory()).path;
    final file = File(p.join(dir, 'history.json'));
    final records = <TransferRecord>[];
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is List) {
          for (final raw in decoded) {
            final r = TransferRecord.tryFromJson(raw);
            if (r != null) records.add(r);
          }
        }
      } catch (_) {
        // Corrupt file: keep a copy for diagnosis and start fresh.
        try {
          await file.rename('${file.path}.corrupt');
        } catch (_) {}
      }
    }
    records.sort((a, b) => b.finishedAt.compareTo(a.finishedAt));
    return HistoryService._(file, records);
  }

  Stream<void> get changes => _changes.stream;
  List<TransferRecord> get records => List.unmodifiable(_records);

  Future<void> add(TransferRecord record) async {
    _records.insert(0, record);
    if (_records.length > maxEntries) {
      _records.removeRange(maxEntries, _records.length);
    }
    _changes.add(null);
    await _persist();
  }

  Future<void> clear() async {
    _records.clear();
    _changes.add(null);
    await _persist();
  }

  /// Writes are chained so two quick transfers never interleave file writes.
  Future<void> _persist() {
    final snapshot = jsonEncode(_records.map((r) => r.toJson()).toList());
    _writeChain = _writeChain.then((_) async {
      try {
        await FileUtils.atomicWrite(_file, snapshot);
      } catch (_) {
        // Disk full / locked: history is best-effort and must not crash transfers.
      }
    });
    return _writeChain;
  }

  Future<void> dispose() async {
    await _writeChain;
    await _changes.close();
  }
}
