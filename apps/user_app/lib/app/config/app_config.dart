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
    required this.mapsApiKey,
  });

  final AppFlavor flavor;
  final String apiBaseUrl;
  final bool enableLogging;

  /// Google Maps/Places key, for calls the app makes DIRECTLY to Google
  /// (Places autocomplete/detail). Android/iOS get their own copy natively
  /// (manifest `MAPS_API_KEY` / `GMSApiKey`) for rendering map tiles — this is
  /// the Dart-visible copy for HTTP calls, supplied at build time:
  ///   --dart-define=MAPS_API_KEY=...
  /// Empty is safe: the Places client falls back to the backend `/geo` proxy.
  final String mapsApiKey;

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

  // Same unrestricted key already baked into the native manifest (via
  // android/local.properties), the admin bundle, and the backend Integration
  // Settings — see MAPS_SETUP.md. Kept as a default so direct Places calls
  // work on a plain build too; --dart-define=MAPS_API_KEY=... still overrides.
  static const String _definedMapsKey = String.fromEnvironment(
    'MAPS_API_KEY',
    defaultValue: 'AIzaSyAVbIGwEi4GeLFmQefqrOcV3Md8bK1Qtoc',
  );

  /// Initializes config for the given [flavor]. Idempotent within a run.
  static AppConfig init({AppFlavor flavor = AppFlavor.prod}) {
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
      mapsApiKey: _definedMapsKey,
    );
  }

  bool get isProd => flavor == AppFlavor.prod;
  bool get isDev => flavor == AppFlavor.dev;

  /// Backend origin without the `/api/v1` suffix — media (`/media/...`) is served
  /// at the host root, not under the API path.
  String get assetOrigin {
    final i = apiBaseUrl.indexOf('/api/');
    return i >= 0 ? apiBaseUrl.substring(0, i) : apiBaseUrl;
  }

  /// Resolve a possibly-relative media path (e.g. `/media/...`) to an absolute URL.
  String assetUrl(String path) {
    if (path.isEmpty || path.startsWith('http')) return path;
    return '$assetOrigin${path.startsWith('/') ? '' : '/'}$path';
  }
}
