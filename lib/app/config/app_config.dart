/// Build-time environment flavors for VS Mart.
enum AppFlavor { dev, staging, prod }

/// Centralized, environment-aware configuration.
///
/// Initialize once at startup via [AppConfig.init] (see `main.dart`), then read
/// the singleton through [AppConfig.instance]. Values can be overridden at build
/// time with `--dart-define` (e.g. `--dart-define=API_BASE_URL=...`).
class AppConfig {
  AppConfig._({
    required this.flavor,
    required this.apiBaseUrl,
    required this.enableLogging,
    required this.bypassAuth,
  });

  final AppFlavor flavor;
  final String apiBaseUrl;
  final bool enableLogging;

  /// Dev-only: when true, the app boots into an authenticated, verified mock
  /// session (skips login/onboarding). Enable with
  /// `--dart-define=DEV_BYPASS_AUTH=true`. Forced off in prod builds.
  final bool bypassAuth;

  static AppConfig? _instance;
  static AppConfig get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('AppConfig.init() must be called before use.');
    }
    return i;
  }

  static const String _definedBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');

  static const bool _definedBypassAuth =
      bool.fromEnvironment('DEV_BYPASS_AUTH', defaultValue: false);

  /// Initializes config for the given [flavor]. Idempotent within a run.
  static AppConfig init({AppFlavor flavor = AppFlavor.dev}) {
    final baseUrl = _definedBaseUrl.isNotEmpty
        ? _definedBaseUrl
        : switch (flavor) {
            // Dev points at the local Django backend over the LAN so a physical
            // phone on the same Wi-Fi can reach it. If the PC's IP changes (or the
            // phone uses the PC's hotspot → 192.168.137.1), override at build time:
            //   --dart-define=API_BASE_URL=http://<pc-ip>:8000/api/v1
            AppFlavor.dev => 'http://192.168.1.9:8000/api/v1',
            AppFlavor.staging => 'https://staging-api.thevsmart.com/api/v1',
            AppFlavor.prod => 'https://api.thevsmart.com/api/v1',
          };

    return _instance = AppConfig._(
      flavor: flavor,
      apiBaseUrl: baseUrl,
      enableLogging: flavor != AppFlavor.prod,
      bypassAuth: flavor != AppFlavor.prod && _definedBypassAuth,
    );
  }

  bool get isProd => flavor == AppFlavor.prod;
  bool get isDev => flavor == AppFlavor.dev;
}
