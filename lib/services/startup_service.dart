import 'dart:io';

/// SERVICE: "Launch at Windows startup" via the per-user Run registry key.
/// Per-user (HKCU) means no administrator rights are needed.
/// Uses PowerShell with the exe path passed through an environment variable,
/// so spaces/quotes in the path cannot break or inject commands.
class StartupService {
  static const String _runKey =
      r'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';
  static const String _valueName = 'Humanize';

  bool get isSupported => Platform.isWindows;

  Future<bool> isEnabled() async {
    if (!isSupported) return false;
    try {
      final r = await _powershell(
        "(Get-ItemProperty -Path '$_runKey' -Name '$_valueName' -ErrorAction SilentlyContinue).'$_valueName'",
      );
      return r.exitCode == 0 && (r.stdout as String).trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Returns null on success or a human-readable error.
  Future<String?> setEnabled(bool enabled) async {
    if (!isSupported) return 'Launch at startup is only available on Windows.';
    try {
      final script = enabled
          ? "Set-ItemProperty -Path '$_runKey' -Name '$_valueName' -Value ('\"' + \$env:HUMANIZE_EXE + '\"')"
          : "Remove-ItemProperty -Path '$_runKey' -Name '$_valueName' -ErrorAction SilentlyContinue";
      final r = await _powershell(script);
      if (r.exitCode != 0) {
        final err = (r.stderr as String).trim();
        return 'Windows refused the startup change${err.isEmpty ? '.' : ': $err'}';
      }
      return null;
    } catch (e) {
      return 'Could not change startup setting: $e';
    }
  }

  Future<ProcessResult> _powershell(String script) {
    return Process.run(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', script],
      environment: {'HUMANIZE_EXE': Platform.resolvedExecutable},
    );
  }
}
