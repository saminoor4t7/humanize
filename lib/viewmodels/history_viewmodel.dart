import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/transfer_record.dart';
import '../services/history_service.dart';

enum DirectionFilter { all, sent, received }

/// VIEWMODEL: searchable, filterable transfer history.
class HistoryViewModel extends ChangeNotifier {
  HistoryViewModel(this._service) {
    _sub = _service.changes.listen((_) => notifyListeners());
  }

  final HistoryService _service;
  late final StreamSubscription<void> _sub;

  String _query = '';
  TransferStatus? _status; // null = all
  DirectionFilter _direction = DirectionFilter.all;

  String get query => _query;
  TransferStatus? get statusFilter => _status;
  DirectionFilter get directionFilter => _direction;

  List<TransferRecord> get allRecords => _service.records;

  List<TransferRecord> get records {
    final q = _query.trim().toLowerCase();
    return _service.records.where((r) {
      if (_status != null && r.status != _status) return false;
      if (_direction == DirectionFilter.sent && !r.isOutgoing) return false;
      if (_direction == DirectionFilter.received && r.isOutgoing) return false;
      if (q.isEmpty) return true;
      return r.fileName.toLowerCase().contains(q) ||
          r.peerName.toLowerCase().contains(q) ||
          r.peerIp.contains(q) ||
          (r.error ?? '').toLowerCase().contains(q);
    }).toList();
  }

  // Dashboard numbers come from persisted history (real data).
  int get completedCount =>
      _service.records.where((r) => r.status == TransferStatus.completed).length;
  int get totalBytesTransferred => _service.records
      .where((r) => r.status == TransferStatus.completed)
      .fold(0, (sum, r) => sum + r.sizeBytes);
  List<TransferRecord> get recent => _service.records.take(5).toList();

  void setQuery(String v) {
    _query = v;
    notifyListeners();
  }

  void setStatus(TransferStatus? s) {
    _status = s;
    notifyListeners();
  }

  void setDirection(DirectionFilter d) {
    _direction = d;
    notifyListeners();
  }

  /// The View must ask the user to confirm before calling this.
  Future<void> clear() => _service.clear();

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
