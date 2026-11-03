/// MODEL: a transfer in progress or finished this session.
///
/// This object is deliberately mutable: the transfer engine updates it
/// thousands of times per second and notifies the UI through a throttled
/// stream, so we avoid allocating a new immutable copy per chunk.
enum TransferDirection { incoming, outgoing }

enum TransferState {
  queued,
  connecting,
  awaitingApproval,
  transferring,
  completed,
  failed,
  cancelled,
  rejected;

  bool get isActive =>
      this == queued ||
      this == connecting ||
      this == awaitingApproval ||
      this == transferring;

  String get label => switch (this) {
        TransferState.queued => 'Queued',
        TransferState.connecting => 'Connecting',
        TransferState.awaitingApproval => 'Waiting for approval',
        TransferState.transferring => 'Transferring',
        TransferState.completed => 'Completed',
        TransferState.failed => 'Failed',
        TransferState.cancelled => 'Cancelled',
        TransferState.rejected => 'Rejected',
      };
}

/// One file inside a transfer.
class TransferFile {
  const TransferFile({
    required this.index,
    required this.fileKey,
    required this.relPath,
    required this.size,
    this.localPath,
    this.modifiedMs,
  });

  final int index;

  /// Stable id (64 hex) used to find a partial download when resuming.
  final String fileKey;

  /// Path relative to the destination, `/` separated. Validated by receiver.
  final String relPath;
  final int size;

  /// Sender side only.
  final String? localPath;
  final int? modifiedMs;
}

/// A file chosen on the Send screen, before it becomes a [TransferFile].
class SendFile {
  const SendFile({
    required this.localPath,
    required this.relPath,
    required this.size,
    required this.modifiedMs,
  });

  final String localPath;
  final String relPath;
  final int size;
  final int modifiedMs;
}

class Transfer {
  Transfer({
    required this.id,
    required this.direction,
    required this.peerName,
    required this.peerIp,
    required this.files,
    this.peerId,
    this.state = TransferState.queued,
  }) : createdAt = DateTime.now();

  final String id;
  final TransferDirection direction;
  final List<TransferFile> files;
  final DateTime createdAt;

  String peerName;
  String peerIp;
  String? peerId;
  bool peerTrusted = false;

  TransferState state;
  int transferredBytes = 0;

  /// Bytes already present from an earlier interrupted attempt.
  int resumedBytes = 0;
  double speedBytesPerSecond = 0;
  int completedFiles = 0;
  String? currentFile;
  String? error;
  DateTime? startedAt;
  DateTime? endedAt;

  int get totalBytes => files.fold(0, (sum, f) => sum + f.size);
  bool get isOutgoing => direction == TransferDirection.outgoing;

  double get progress {
    final total = totalBytes;
    if (total == 0) return state == TransferState.completed ? 1 : 0;
    return (transferredBytes / total).clamp(0.0, 1.0);
  }

  /// Remaining time from real measured speed; null when unknown.
  Duration? get eta {
    if (state != TransferState.transferring || speedBytesPerSecond < 1) {
      return null;
    }
    final remaining = totalBytes - transferredBytes;
    if (remaining <= 0) return Duration.zero;
    return Duration(seconds: (remaining / speedBytesPerSecond).ceil());
  }

  Duration get elapsed =>
      (endedAt ?? DateTime.now()).difference(startedAt ?? createdAt);

  String get displayName {
    if (files.isEmpty) return '(no files)';
    if (files.length == 1) return files.first.relPath;
    return '${files.first.relPath} (+${files.length - 1} more)';
  }
}
