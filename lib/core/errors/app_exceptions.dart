/// Base type for all expected, user-presentable failures.
/// Anything that is NOT a [HumanizeException] is an unexpected bug or an
/// OS-level I/O error and is wrapped with a friendly message at the boundary.
class HumanizeException implements Exception {
  const HumanizeException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The peer violated the wire protocol (bad frame, wrong order, bad JSON...).
class ProtocolException extends HumanizeException {
  const ProtocolException(super.message);
}

/// Peer identity could not be proven.
class AuthException extends HumanizeException {
  const AuthException(super.message);
}

/// A file name / relative path failed safety validation.
class PathValidationException extends HumanizeException {
  const PathValidationException(super.message);
}

/// Connecting to a peer failed (timeout, refused, TLS failure...).
class ConnectionFailedException extends HumanizeException {
  const ConnectionFailedException(super.message);
}

/// No data arrived within the allowed idle time.
class ConnectionTimeoutException extends HumanizeException {
  const ConnectionTimeoutException(super.message);
}

/// The transfer was cancelled (by this user or by the peer).
class TransferCancelledException extends HumanizeException {
  const TransferCancelledException(super.message);
}

/// SHA-256 or size verification of a received file failed.
class IntegrityException extends HumanizeException {
  const IntegrityException(super.message);
}
