import 'dart:io';

import 'package:path/path.dart' as p;

import '../constants/protocol_constants.dart';
import '../errors/app_exceptions.dart';

/// Validates untrusted file names from the network and keeps writes inside
/// the destination folder (no path traversal, no Windows device names).
class PathSanitizer {
  PathSanitizer._();

  static const int maxSegmentLength = 255;
  static const int maxDepth = 32;

  static final RegExp _invalidChars = RegExp(r'[<>:"|?*\x00-\x1F]');
  static const Set<String> _reservedNames = {
    'con', 'prn', 'aux', 'nul',
    'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
    'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
  };

  /// Splits a peer-supplied relative path (either `/` or `\` separated) into
  /// validated segments, or throws [PathValidationException].
  static List<String> splitAndValidate(String raw) {
    if (raw.isEmpty || raw.length > ProtocolConstants.maxRelativePathLength) {
      throw const PathValidationException('File name is empty or too long.');
    }
    if (raw.startsWith('/') || raw.startsWith('\\')) {
      throw const PathValidationException('Absolute paths are not allowed.');
    }
    final segments = raw.split(RegExp(r'[\\/]'));
    if (segments.length > maxDepth) {
      throw const PathValidationException('Folder nesting is too deep.');
    }
    for (final s in segments) {
      _validateSegment(s);
    }
    if (segments.first.toLowerCase() == ProtocolConstants.partialDirName) {
      throw const PathValidationException('Reserved folder name.');
    }
    return segments;
  }

  static void _validateSegment(String s) {
    if (s.isEmpty) {
      throw const PathValidationException('Empty path segment.');
    }
    if (s == '.' || s == '..') {
      throw const PathValidationException('Relative path segments are not allowed.');
    }
    if (s.length > maxSegmentLength) {
      throw const PathValidationException('A file or folder name is too long.');
    }
    if (_invalidChars.hasMatch(s)) {
      throw const PathValidationException('File name contains invalid characters.');
    }
    if (s.endsWith('.') || s.endsWith(' ')) {
      throw const PathValidationException('File names cannot end with a dot or space.');
    }
    final stem = s.split('.').first.trim().toLowerCase();
    if (_reservedNames.contains(stem)) {
      throw const PathValidationException('Reserved Windows device name.');
    }
  }

  /// Joins [segments] under [root] and verifies the result stays inside it.
  static String resolveInside(String root, List<String> segments) {
    final rootNorm = p.normalize(p.absolute(root));
    final resolved = p.normalize(p.joinAll([rootNorm, ...segments]));
    if (!p.isWithin(rootNorm, resolved)) {
      throw const PathValidationException('Path escapes the destination folder.');
    }
    return resolved;
  }

  /// If [path] exists, returns "name (1).ext", "name (2).ext", ... instead.
  static String uniquePath(String path) {
    bool exists(String x) => File(x).existsSync() || Directory(x).existsSync();
    if (!exists(path)) return path;
    final dir = p.dirname(path);
    final ext = p.extension(path);
    final base = p.basenameWithoutExtension(path);
    for (var i = 1; i < 10000; i++) {
      final candidate = p.join(dir, '$base ($i)$ext');
      if (!exists(candidate)) return candidate;
    }
    throw const PathValidationException('Could not find a free file name.');
  }
}
