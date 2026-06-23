import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/config/app_config.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../address/presentation/providers/address_providers.dart';
import '../../../billing/presentation/providers/billing_providers.dart';
import '../../../cart/presentation/providers/cart_providers.dart';
import '../../../credit/presentation/providers/credit_providers.dart';
import '../../../notifications/presentation/providers/notification_providers.dart';
import '../../../orders/presentation/providers/order_providers.dart';
import '../../../wishlist/presentation/providers/wishlist_providers.dart';
import '../../data/models/user_model.dart';
import '../../domain/entities/user.dart';

/// High-level authentication status used to drive routing.
enum AuthStatus { unknown, authenticated, unauthenticated }

class SessionState extends Equatable {
  const SessionState({required this.status, this.user});

  final AuthStatus status;
  final User? user;

  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get needsKyc =>
      isAuthenticated && (user != null && !user!.isKycVerified);
  bool get needsRegistration =>
      isAuthenticated && (user != null && !user!.hasProfile);

  SessionState copyWith({AuthStatus? status, User? user}) =>
      SessionState(status: status ?? this.status, user: user ?? this.user);

  @override
  List<Object?> get props => [status, user];
}

/// Owns the authenticated session. Initialized synchronously from local storage
/// so the router can redirect immediately on cold start; the network confirms
/// and refreshes the user afterwards (see `current_user_provider`).
class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() {
    final local = ref.read(localUserStorageProvider);

    // Dev-only auth bypass: boot straight into a verified, approved session so
    // login/onboarding can be skipped during testing. Never active in prod.
    if (AppConfig.instance.bypassAuth && !local.isLoggedIn) {
      return SessionState(status: AuthStatus.authenticated, user: _devUser);
    }

    User? user;
    final json = local.getUser();
    if (json != null) {
      try {
        user = UserModel.fromJson(json).toEntity();
      } catch (_) {
        user = null;
      }
    }
    return SessionState(
      status:
          local.isLoggedIn ? AuthStatus.authenticated : AuthStatus.unauthenticated,
      user: user,
    );
  }

  /// Mark the session authenticated with a known [user].
  void setAuthenticated(User user) =>
      state = SessionState(status: AuthStatus.authenticated, user: user);

  /// Update only the user (e.g. after profile/KYC refresh).
  void setUser(User user) => state = state.copyWith(user: user);

  /// Clear local credentials and flip to unauthenticated (used on logout/401).
  Future<void> clearLocalSession() async {
    await ref.read(tokenStorageProvider).clear();
    await ref.read(localUserStorageProvider).clear();
    _resetUserScopedProviders();
    state = const SessionState(status: AuthStatus.unauthenticated);
  }

  /// Drop in-memory provider state so nothing leaks to the next account on this
  /// device (Hive is wiped separately by HiveService.clearAll() on logout).
  void _resetUserScopedProviders() {
    ref.invalidate(cartControllerProvider);
    ref.invalidate(addressesProvider);
    ref.invalidate(ordersProvider);
    ref.invalidate(creditAccountProvider);
    ref.invalidate(creditTransactionsProvider);
    ref.invalidate(wishlistProvider);
    ref.invalidate(notificationsProvider);
    ref.invalidate(creditLedgerProvider);
    ref.invalidate(statementsProvider);
  }
}

/// Mock customer used by the dev auth bypass (verified + credit-enabled so the
/// router treats it as fully approved and lands on Home).
final User _devUser = User(
  id: 'dev-user',
  phone: '+919999999999',
  name: 'Test User',
  email: 'test@vsmart.app',
  kycStatus: KycStatus.verified,
  creditEnabled: true,
  createdAt: DateTime(2025, 1, 1),
);

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

/// Convenience selector for the high-level auth status.
final authStatusProvider = Provider<AuthStatus>(
  (ref) => ref.watch(sessionControllerProvider).status,
);
