import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/constants/protocol_constants.dart';
import '../core/utilities/fingerprint.dart';
import '../core/utilities/hash_utils.dart';

/// What the receiver already has of a file from an interrupted attempt.
class PartialState {
  PartialState(this.offset, this.prefixSha256, this.running);

  final int offset;

  /// SHA-256 of the first [offset] bytes, sent to the sender for validation.
  final String prefixSha256;

  /// Open hash state that has consumed the prefix; continue it with new data.
  final Sha256Accumulator running;
}

/// SERVICE: partial-download files and their metadata (for resume).
///
/// Layout inside the download folder:
///   .humanize-partial/<senderId16>_<fileKey32>.part   (bytes received so far)
///   .humanize-partial/<senderId16>_<fileKey32>.json   (what the file is)
///
/// Names are built only from validated lowercase hex, never from peer-supplied
/// file names, so a peer cannot choose where partial data is written.
class PartialStore {
  PartialStore(this.downloadDir);

  final String downloadDir;

  Directory get _dir => Directory(p.join(downloadDir, ProtocolConstants.partialDirName));

  String _base(String senderId, String fileKey) {
    assert(Fingerprint.isValid(senderId) && Fingerprint.isValid(fileKey));
    return '${senderId.substring(0, 16)}_${fileKey.substring(0, 32)}';
  }

  File partFile(String senderId, String fileKey) =>
      File(p.join(_dir.path, '${_base(senderId, fileKey)}.part'));

  File _metaFile(String senderId, String fileKey) =>
      File(p.join(_dir.path, '${_base(senderId, fileKey)}.json'));

  /// Records metadata for a file that is about to be received.
  Future<void> begin(String senderId, String fileKey, String relPath, int size) async {
    await _dir.create(recursive: true);
    await _metaFile(senderId, fileKey).writeAsString(jsonEncode({
      'fileKey': fileKey,
      'relPath': relPath,
      'size': size,
      'createdAt': DateTime.now().toIso8601String(),
    }));
  }

  /// Returns validated resume info, or null (and cleans up) if the leftovers
  /// are unusable. Validation: metadata matches, file is non-empty and
  /// shorter than the full size, and its prefix is hashed for the sender.
  Future<PartialState?> inspect(String senderId, String fileKey, int size) async {
    final part = partFile(senderId, fileKey);
    final meta = _metaFile(senderId, fileKey);
    try {
      if (!await part.exists() || !await meta.exists()) {
        await discard(senderId, fileKey);
        return null;
      }
      final m = jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
      if (m['fileKey'] != fileKey || m['size'] != size) {
        await discard(senderId, fileKey);
        return null;
      }
      final length = await part.length();
      if (length <= 0 || length >= size) {
        await discard(senderId, fileKey);
        return null;
      }
      final ph = await hashPrefix(part, length);
      return PartialState(length, ph.prefixHex, ph.running);
    } catch (_) {
      await discard(senderId, fileKey);
      return null;
    }
  }

  /// Securely removes leftovers (used on cancel, corruption, expiry).
  Future<void> discard(String senderId, String fileKey) async {
    for (final f in [partFile(senderId, fileKey), _metaFile(senderId, fileKey)]) {
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  Future<void> deleteMeta(String senderId, String fileKey) async {
    try {
      final f = _metaFile(senderId, fileKey);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Deletes partial files older than [maxAge] so abandoned transfers do not
  /// pile up on disk.
  Future<void> purgeExpired([Duration maxAge = ProtocolConstants.partialMaxAge]) async {
    try {
      if (!await _dir.exists()) return;
      final cutoff = DateTime.now().subtract(maxAge);
      await for (final e in _dir.list(followLinks: false)) {
        if (e is! File) continue;
        final stat = await e.stat();
        if (stat.modified.isBefore(cutoff)) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
