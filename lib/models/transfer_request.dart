import 'dart:async';

import 'transfer.dart';

/// MODEL: an incoming transfer waiting for the user's decision.
class TransferRequest {
  TransferRequest({
    required this.id,
    required this.peerId,
    required this.peerName,
    required this.peerIp,
    required this.trusted,
    required this.files,
  }) : receivedAt = DateTime.now();

  final String id;
  final String peerId;
  final String peerName;
  final String peerIp;

  /// True only if the user previously trusted this exact identity.
  final bool trusted;
  final List<TransferFile> files;
  final DateTime receivedAt;

  final Completer<bool> decision = Completer<bool>();

  int get totalBytes => files.fold(0, (sum, f) => sum + f.size);

  void accept() {
    if (!decision.isCompleted) decision.complete(true);
  }

  void reject() {
    if (!decision.isCompleted) decision.complete(false);
  }
}
