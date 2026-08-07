/// Resolves a notification's `route` payload to a go_router **path**.
///
/// The backend puts a destination in `data.route`. It may be a bare name
/// (`"offers"`) or an absolute path with parameters (`"/orders/VS12345"`).
///
/// This exists because the two consumers had drifted: the push handler treated
/// the value as a *path* (`go('/orders/123')`) while the in-app notification
/// list treated the same string as a *route name* (`pushNamed('/orders/123')`),
/// which throws. Every parameterized notification — order, invoice, statement,
/// ticket — dead-ended when tapped inside the app.
///
/// Paths win because they carry their parameters; a name cannot without a
/// separate argument map the backend has no way to express.
String? resolveNotificationPath(Object? raw) {
  if (raw is! String) return null;
  final value = raw.trim();
  if (value.isEmpty) return null;
  // Reject anything that looks like an absolute URL — a notification must not
  // be able to send the app to an arbitrary destination.
  if (value.contains('://')) return null;
  return value.startsWith('/') ? value : '/$value';
}
