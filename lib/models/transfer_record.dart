/// MODEL: one finished transfer as stored in history.
/// Only metadata is stored. File contents are never written to history.
enum TransferStatus {
  completed,
  failed,
  cancelled,
  rejected;

  String get label => switch (this) {
        TransferStatus.completed => 'Completed',
        TransferStatus.failed => 'Failed',
        TransferStatus.cancelled => 'Cancelled',
        TransferStatus.rejected => 'Rejected',
      };
}

class TransferRecord {
  const TransferRecord({
    required this.id,
    required this.fileName,
    required this.fileCount,
    required this.sizeBytes,
    required this.peerName,
    required this.peerIp,
    required this.isOutgoing,
    required this.finishedAt,
    required this.duration,
    required this.status,
    this.error,
  });

  final String id;
  final String fileName;
  final int fileCount;
  final int sizeBytes;
  final String peerName;
  final String peerIp;
  final bool isOutgoing;
  final DateTime finishedAt;
  final Duration duration;
  final TransferStatus status;
  final String? error;

  /// Average speed from real bytes over real elapsed time.
  double get averageMbPerSecond {
    final seconds = duration.inMilliseconds / 1000;
    if (seconds <= 0) return 0;
    return (sizeBytes / (1024 * 1024)) / seconds;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'fileName': fileName,
        'fileCount': fileCount,
        'sizeBytes': sizeBytes,
        'peerName': peerName,
        'peerIp': peerIp,
        'isOutgoing': isOutgoing,
        'finishedAt': finishedAt.toIso8601String(),
        'durationMs': duration.inMilliseconds,
        'status': status.name,
        'error': error,
      };

  static TransferRecord? tryFromJson(Object? raw) {
    try {
      final m = raw as Map<String, dynamic>;
      return TransferRecord(
        id: m['id'] as String,
        fileName: m['fileName'] as String,
        fileCount: m['fileCount'] as int,
        sizeBytes: m['sizeBytes'] as int,
        peerName: m['peerName'] as String,
        peerIp: m['peerIp'] as String,
        isOutgoing: m['isOutgoing'] as bool,
        finishedAt: DateTime.parse(m['finishedAt'] as String),
        duration: Duration(milliseconds: m['durationMs'] as int),
        status: TransferStatus.values.byName(m['status'] as String),
        error: m['error'] as String?,
      );
    } catch (_) {
      return null; // Skip corrupt entries instead of losing all history.
    }
  }
}
