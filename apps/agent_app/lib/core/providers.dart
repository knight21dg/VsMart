import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';
import 'token_store.dart';

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

/// Selected bottom-nav tab (Home 0 · Collections 1 · Deliveries 2 · Tasks 3 ·
/// Profile 4). Shared so dashboard quick-actions can switch tabs.
final homeTabProvider = StateProvider<int>((ref) => 0);

final apiProvider = Provider<Api>((ref) {
  return Api(
    ref.watch(tokenStoreProvider),
    onLogout: () async => ref.read(authStatusProvider.notifier).logout(),
  );
});

/// High-level auth state driving the router.
enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthController extends Notifier<AuthStatus> {
  @override
  AuthStatus build() {
    _init();
    return AuthStatus.unknown;
  }

  Future<void> _init() async {
    try {
      final loggedIn = await ref.read(tokenStoreProvider).isLoggedIn;
      state = loggedIn ? AuthStatus.authenticated : AuthStatus.unauthenticated;
    } catch (_) {
      // A secure-storage read failure must not wedge the splash on `unknown`.
      state = AuthStatus.unauthenticated;
    }
  }

  void setAuthenticated() => state = AuthStatus.authenticated;

  Future<void> logout() async {
    // Best-effort server-side revoke (blacklists the refresh token + deactivates
    // device tokens) before clearing locally; never block logout on it.
    try {
      final refresh = await ref.read(tokenStoreProvider).refresh;
      if (refresh != null && refresh.isNotEmpty) {
        await ref.read(apiProvider).post('/auth/logout', data: {'refresh': refresh});
      }
    } catch (_) {
      // offline / already-expired — proceed with local clear anyway
    }
    await ref.read(tokenStoreProvider).clear();
    state = AuthStatus.unauthenticated;
  }
}

final authStatusProvider =
    NotifierProvider<AuthController, AuthStatus>(AuthController.new);
