/// App-wide UI constants and defaults. No magic numbers elsewhere.
class AppConstants {
  AppConstants._();

  static const String appName = 'Humanize';
  static const String appTagline = 'Offline LAN file transfer';
  static const String appVersion = '1.0.0';

  static const int defaultPort = 52525;
  static const int minPort = 1024;
  static const int maxPort = 65535;

  static const int defaultMaxConcurrentTransfers = 3;
  static const int maxConcurrentTransfersLimit = 10;

  static const int defaultMaxFileSizeMb = 10240; // 10 GB
  static const int maxFileSizeMbLimit = 1048576; // 1 TB

  static const int defaultChunkSizeKb = 256;
  static const int minChunkSizeKb = 16;
  static const int maxChunkSizeKb = 4096;

  static const double sidebarWidth = 248;
  static const double radiusL = 20;
  static const double radiusM = 14;
  static const double radiusS = 10;
}
