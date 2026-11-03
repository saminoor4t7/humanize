import 'dart:io';

/// Crash-safe small-file writes: write a temp file, then rename over target.
class FileUtils {
  FileUtils._();

  static Future<void> atomicWrite(File target, String contents) async {
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(contents, flush: true);
    await tmp.rename(target.path);
  }
}
