/// Wire-protocol and networking constants.
///
/// Humanize wire protocol v1
/// -------------------------
/// Every message is one FRAME on a TLS-over-TCP stream:
///
///   +----------------+-----------+----------------------+
///   | length (u32 BE)| type (u8) | payload (length-1 B) |
///   +----------------+-----------+----------------------+
///
/// `length` counts the type byte plus the payload. Control frames carry UTF-8
/// JSON; CHUNK frames carry raw file bytes. TCP is a byte stream, so the reader
/// always reassembles frames from however many socket reads it takes.
class ProtocolConstants {
  ProtocolConstants._();

  static const int version = 1;

  // Message types.
  static const int hello = 0x01; // client -> server: identity + nonce
  static const int challenge = 0x02; // server -> client: identity + nonce + signature
  static const int auth = 0x03; // client -> server: signature
  static const int authOk = 0x04; // server -> client
  static const int transferRequest = 0x10; // client -> server: manifest
  static const int transferResponse = 0x11; // server -> client: accept/reject + resume info
  static const int fileStart = 0x20; // {index, offset}
  static const int chunk = 0x21; // raw bytes
  static const int fileEnd = 0x22; // {index, size, sha256}
  static const int fileResult = 0x23; // {index, ok, error?}
  static const int sessionDone = 0x30;
  static const int cancel = 0x40; // {reason}
  static const int error = 0x41; // {code, message}

  /// Control frames (everything except CHUNK) are capped to stop memory abuse.
  static const int maxControlPayload = 1024 * 1024; // 1 MiB
  static const int maxChunkPayload = 8 * 1024 * 1024; // 8 MiB hard ceiling

  static const int maxFilesPerTransfer = 20000;
  static const int maxRelativePathLength = 1024;

  // Timing.
  static const Duration connectTimeout = Duration(seconds: 8);
  static const Duration handshakeTimeout = Duration(seconds: 15);
  static const Duration idleTimeout = Duration(seconds: 30);
  static const Duration approvalTimeout = Duration(seconds: 60);
  /// Sender waits slightly longer than the receiver's approval window.
  static const Duration approvalWait = Duration(seconds: 75);

  // Discovery (UDP broadcast).
  static const int discoveryPort = 52526;
  static const Duration announceInterval = Duration(seconds: 5);
  static const Duration deviceOfflineAfter = Duration(seconds: 20);
  static const Duration deviceForgetAfter = Duration(minutes: 10);
  static const int maxDiscoveredDevices = 256;

  // Resume.
  static const String partialDirName = '.humanize-partial';
  static const Duration partialMaxAge = Duration(days: 7);
}
