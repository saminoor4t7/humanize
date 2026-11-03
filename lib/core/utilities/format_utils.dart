/// Human-readable formatting helpers (pure functions, easy to unit test).
class FormatUtils {
  FormatUtils._();

  static String bytes(int value) {
    if (value < 1024) return '$value B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    double size = value / 1024;
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(size >= 100 ? 0 : 1)} ${units[unit]}';
  }

  /// Speed from measured bytes/second, always shown in MB/s as requested.
  static String speed(double bytesPerSecond) {
    final mb = bytesPerSecond / (1024 * 1024);
    return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB/s';
  }

  static String duration(Duration d) {
    if (d.inSeconds < 1) return '${d.inMilliseconds} ms';
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    if (d.inHours < 1) {
      return '${d.inMinutes}m ${(d.inSeconds % 60).toString().padLeft(2, '0')}s';
    }
    return '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m';
  }

  static String dateTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}
