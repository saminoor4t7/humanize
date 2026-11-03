import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../core/constants/protocol_constants.dart';
import '../core/errors/app_exceptions.dart';

/// One protocol frame. See [ProtocolConstants] for the wire layout.
class Frame {
  const Frame(this.type, this.payload);

  final int type;
  final Uint8List payload;

  /// Decodes a control frame's JSON object, or throws [ProtocolException].
  Map<String, dynamic> json() {
    try {
      final decoded = jsonDecode(utf8.decode(payload));
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // fall through
    }
    throw const ProtocolException('Malformed control message.');
  }
}

/// Writes length-prefixed frames to a socket.
///
/// `await flush()` after each frame gives backpressure: if the network is
/// slower than the disk, we stop reading the file until the OS has drained
/// the socket. Memory use therefore stays bounded to about one chunk.
class FrameWriter {
  FrameWriter(this._socket);

  final Socket _socket;

  Future<void> writeJson(int type, Map<String, Object?> body) =>
      writeBytes(type, Uint8List.fromList(utf8.encode(jsonEncode(body))));

  Future<void> writeBytes(int type, Uint8List payload) async {
    final isChunk = type == ProtocolConstants.chunk;
    final limit = isChunk
        ? ProtocolConstants.maxChunkPayload
        : ProtocolConstants.maxControlPayload;
    if (payload.length > limit) {
      throw const ProtocolException('Frame is too large.');
    }
    final header = ByteData(5)
      ..setUint32(0, payload.length + 1) // big-endian: length incl. type byte
      ..setUint8(4, type);
    _socket.add(header.buffer.asUint8List());
    if (payload.isNotEmpty) _socket.add(payload);
    await _socket.flush();
  }
}

/// Reassembles frames from a TCP byte stream.
///
/// TCP gives no message boundaries: one socket read may hold half a header,
/// several frames, or one byte. [_readExactly] therefore loops until it has
/// precisely the number of bytes asked for, whatever the read sizes were.
/// The StreamIterator only pulls the next socket event when we need it, so a
/// slow consumer naturally slows the sender (TCP flow control).
class FrameReader {
  FrameReader(Stream<Uint8List> stream) : _it = StreamIterator<Uint8List>(stream);

  final StreamIterator<Uint8List> _it;
  Uint8List _buf = Uint8List(0);
  int _pos = 0;

  Future<bool> _fill(Duration? timeout) async {
    final Future<bool> pending = _it.moveNext();
    final bool more;
    try {
      more = timeout == null ? await pending : await pending.timeout(timeout);
    } on TimeoutException {
      throw const ConnectionTimeoutException(
          'The other computer stopped responding.');
    }
    if (!more) return false;
    _buf = _it.current;
    _pos = 0;
    return true;
  }

  /// Reads exactly [n] bytes. Returns null only for a clean EOF at the very
  /// start of a read when [allowEof] is true; EOF anywhere else is an error.
  Future<Uint8List?> _readExactly(int n, Duration? timeout, {bool allowEof = false}) async {
    final out = Uint8List(n);
    var filled = 0;
    while (filled < n) {
      if (_pos >= _buf.length) {
        final more = await _fill(timeout);
        if (!more) {
          if (allowEof && filled == 0) return null;
          throw const ProtocolException(
              'Connection closed unexpectedly (incomplete data).');
        }
        continue;
      }
      final take = min(n - filled, _buf.length - _pos);
      out.setRange(filled, filled + take, _buf, _pos);
      filled += take;
      _pos += take;
    }
    return out;
  }

  /// Next frame, or null on a clean end of stream between frames.
  Future<Frame?> readFrame({Duration? timeout}) async {
    final header = await _readExactly(5, timeout, allowEof: true);
    if (header == null) return null;
    final bd = ByteData.sublistView(header);
    final length = bd.getUint32(0);
    final type = bd.getUint8(4);
    if (length < 1) throw const ProtocolException('Invalid frame length.');
    final payloadLength = length - 1;
    final limit = type == ProtocolConstants.chunk
        ? ProtocolConstants.maxChunkPayload
        : ProtocolConstants.maxControlPayload;
    // Reject BEFORE allocating so a hostile peer cannot make us allocate GBs.
    if (payloadLength > limit) {
      throw const ProtocolException('Frame exceeds the allowed size.');
    }
    final payload = payloadLength == 0
        ? Uint8List(0)
        : (await _readExactly(payloadLength, timeout))!;
    return Frame(type, payload);
  }

  /// Next frame; throws if the connection is closed.
  Future<Frame> next({Duration? timeout}) async {
    final f = await readFrame(timeout: timeout);
    if (f == null) throw const ProtocolException('Connection closed by the other computer.');
    return f;
  }

  Future<void> cancel() async {
    try {
      await _it.cancel();
    } catch (_) {
      // Socket already failed; nothing to clean up.
    }
  }
}
