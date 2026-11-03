/// Measures speed from ACTUAL bytes over a sliding time window.
/// Never estimates or smooths beyond the window, so it cannot report speeds
/// the network/disk did not deliver.
class SpeedMeter {
  SpeedMeter({this.window = const Duration(seconds: 3), DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final Duration window;
  final DateTime Function() _clock;
  final List<(int, int)> _samples = []; // (epoch ms, cumulative bytes)

  /// Record the cumulative byte count moved so far.
  void record(int cumulativeBytes) {
    final now = _clock().millisecondsSinceEpoch;
    // Coalesce samples closer than 50 ms to keep the list tiny.
    if (_samples.isNotEmpty && now - _samples.last.$1 < 50) {
      _samples[_samples.length - 1] = (now, cumulativeBytes);
      return;
    }
    _samples.add((now, cumulativeBytes));
    final cutoff = now - window.inMilliseconds;
    while (_samples.length > 2 && _samples.first.$1 < cutoff) {
      _samples.removeAt(0);
    }
  }

  double get bytesPerSecond {
    if (_samples.length < 2) return 0;
    final a = _samples.first;
    final b = _samples.last;
    final seconds = (b.$1 - a.$1) / 1000;
    if (seconds <= 0) return 0;
    return (b.$2 - a.$2) / seconds;
  }

  void reset() => _samples.clear();
}
