import '../../app/config/app_config.dart';

/// Helpers for deciding whether an image URL points at one of *our* private,
/// auth-gated media endpoints (KYC docs, delivery POD, verification evidence,
/// generic private assets) and therefore needs an `Authorization: Bearer`
/// header attached to its request.
///
/// The backend serves private media behind authenticated `/api/v1/` endpoints
/// (e.g. `/api/v1/kyc/documents/<id>/file`,
/// `/api/v1/delivery/deliveries/<id>/proof-photo`,
/// `/api/v1/verification/evidence/<id>/photo`,
/// `/api/v1/media/<uuid>/<variant>`). **Public** media
/// (`/api/v1/media/public/<uuid>/<variant>`) and external catalog image URLs
/// load without auth and must NOT receive the bearer token.
abstract final class MediaAuth {
  MediaAuth._();

  /// Path segment that marks *public* (no-auth) media on our own host.
  static const String _publicMediaMarker = '/media/public/';

  /// Returns true only when [url] is one of our own private API media URLs:
  /// it must be an absolute URL on the configured API origin, and must NOT be a
  /// `/media/public/...` path. External URLs (catalog CDNs, gravatar, etc.) and
  /// relative/asset paths classify as NOT private.
  ///
  /// Public avatar URLs (`/api/v1/media/public/...`) classify as NOT private.
  static bool isPrivateApiMedia(String? url) {
    if (url == null || url.isEmpty) return false;
    // Only absolute http(s) URLs can be on our host. Asset/relative paths are
    // never private API media.
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return false;
    }

    final origin = _apiOrigin();
    if (origin == null) return false;

    // Must be on our API host:port (origin == scheme://host[:port]).
    final urlOrigin = '${uri.scheme}://${uri.host}'
        '${uri.hasPort ? ':${uri.port}' : ''}';
    if (urlOrigin.toLowerCase() != origin.toLowerCase()) return false;

    // Public media never needs auth, even though it lives on our host.
    if (uri.path.contains(_publicMediaMarker)) return false;

    return true;
  }

  /// The scheme://host[:port] of the configured API base URL, or null if it
  /// can't be parsed.
  static String? _apiOrigin() {
    final base = Uri.tryParse(AppConfig.instance.apiBaseUrl);
    if (base == null || !base.hasScheme) return null;
    return '${base.scheme}://${base.host}'
        '${base.hasPort ? ':${base.port}' : ''}';
  }
}
