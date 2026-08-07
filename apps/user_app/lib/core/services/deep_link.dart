/// Maps an incoming OS deep link (Android App Link / iOS Universal Link) onto an
/// in-app route.
///
/// A deep link is UNTRUSTED input: anyone can craft one and get the OS to hand it
/// to us. So this is an explicit allowlist of link shapes we publish, not a
/// generic URL→path translator. Anything unrecognised returns null and the app
/// opens normally — never a blank screen, never an arbitrary destination.
///
/// The sibling [resolveNotificationPath] does the same job for push payloads and
/// deliberately rejects anything containing `://`; that stays as it is. Deep
/// links *are* absolute URLs, so they get this separate, host-checked path.
library;

/// Hosts whose links we accept. A link from anywhere else is ignored, so an
/// attacker cannot register a lookalike domain and drive the app with it.
const Set<String> kDeepLinkHosts = {
  'thevsmart.com',
  'www.thevsmart.com',
};

/// Custom scheme for links that can't be https (e.g. an OAuth-style return).
/// Accepted only for the same allowlisted paths below.
const String kDeepLinkScheme = 'vsmart';

/// Path prefixes we publish links for, mapped to the in-app route they open.
///
/// Kept narrow on purpose: today the only link we actually hand out is a product
/// share link. Widening this is a deliberate act — every entry here is a URL a
/// stranger can send a customer that changes what their app displays.
const Map<String, String> _pathAliases = {
  // The web product page is `/products/<shareToken>`; the app route is the same
  // shape, so it passes through untouched (see ShareService.productLink).
  '/products': '/products',
  // The landing site 301s singular → plural; accept both so an older shared
  // link still lands in the app instead of bouncing to the browser.
  '/product': '/products',
};

/// Resolves [uri] to an in-app route path, or null when the link isn't one of
/// ours (wrong host, unknown section, or missing its identifier).
String? resolveDeepLink(Uri uri) {
  final isWeb = uri.scheme == 'https' && kDeepLinkHosts.contains(uri.host);
  // For the custom scheme the "host" is the first path segment, e.g.
  // vsmart://products/abc123 — normalise it to look like the web form.
  final isCustom = uri.scheme == kDeepLinkScheme;
  if (!isWeb && !isCustom) return null;

  final segments = <String>[
    if (isCustom && uri.host.isNotEmpty) uri.host,
    ...uri.pathSegments,
  ].where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return null;

  final target = _pathAliases['/${segments.first}'];
  if (target == null) return null;

  // Every allowlisted section is a detail route needing exactly one identifier.
  // Bail on a bare `/products` (nothing to show) and on extra segments, which
  // would mean a link shape we don't publish.
  if (segments.length != 2) return null;
  final id = segments[1].trim();
  if (id.isEmpty) return null;
  // Guard the path separator explicitly: Uri already splits on '/', but an
  // encoded one would otherwise smuggle a second segment into the route.
  if (id.contains('/') || id.contains('..')) return null;

  return '$target/${Uri.encodeComponent(id)}';
}
