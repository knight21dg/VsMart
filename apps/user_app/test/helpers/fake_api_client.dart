import 'package:user_app/core/network/api_client.dart';

/// An [ApiClient] whose every call fails fast, so controllers with best-effort
/// server sync (wishlist, etc.) exercise their offline / optimistic + try-catch
/// paths deterministically in unit tests — no real network, no plugin reads.
class FakeApiClient implements ApiClient {
  // Throw synchronously (not Future.error) so the caller's `try { await ... }`
  // catches it cleanly without the test zone flagging an unhandled async error.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('FakeApiClient: no network in tests');
}
