import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/domain/entities/user.dart';
import '../../features/auth/presentation/providers/current_user_provider.dart';
import '../../features/auth/presentation/providers/session_provider.dart';
import 'route_paths.dart';

/// Where a user sits in the auth + verification lifecycle. Drives the GoRouter
/// redirect so users can't skip steps or reach restricted routes directly.
enum UserStage {
  unauthenticated,
  registrationIncomplete,
  verificationNotStarted,
  verificationPending,
  verificationRejected,
  approved,
}

/// Session guard — is there an authenticated session?
final sessionGuardProvider = Provider<bool>(
  (ref) => ref.watch(authStatusProvider) == AuthStatus.authenticated,
);

/// Verification sub-stage for an authenticated, registered user.
enum VerificationStage { notStarted, pending, rejected, approved }

final verificationGuardProvider = Provider<VerificationStage?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  return switch (user.kycStatus) {
    KycStatus.verified => VerificationStage.approved,
    KycStatus.rejected => VerificationStage.rejected,
    KycStatus.pending => VerificationStage.pending,
    KycStatus.notStarted => VerificationStage.notStarted,
  };
});

/// Combined lifecycle stage. The router watches this to recompute redirects.
///
/// KYC is OPTIONAL: once a user is authenticated and has completed registration
/// they get full app access (stage [UserStage.approved]). KYC/verification is
/// only needed to unlock CREDIT, and is gated inside the credit screens — it
/// never blocks browsing/ordering. [verificationGuardProvider] still exposes the
/// real KYC sub-stage for those screens.
final authGuardProvider = Provider<UserStage>((ref) {
  if (!ref.watch(sessionGuardProvider)) return UserStage.unauthenticated;
  final user = ref.watch(currentUserProvider);
  if (user == null || !user.hasProfile) {
    return UserStage.registrationIncomplete;
  }
  return UserStage.approved;
});

/// Locations an unauthenticated visitor may access. Includes [RoutePaths.register]
/// so the "Create Account" link on login can open the sign-up screen (otherwise
/// the redirect bounces visitors straight back to login), plus the legal pages so
/// the login Terms/Privacy links open instead of bouncing to login.
const Set<String> kVisitorLocations = {
  RoutePaths.onboarding,
  RoutePaths.login,
  RoutePaths.otp,
  RoutePaths.register,
  RoutePaths.terms,
  RoutePaths.privacyPolicy,
};

/// Path prefixes a *guest* (browsing without signing in) must log in to reach.
/// Sub-paths count too (e.g. `/orders/123`). The bare shell-tab roots
/// (home/categories/cart/credit/account) stay browsable — only deeper personal
/// or transactional routes gate, so the "buy → sign in" moment is enforced while
/// the rest of the app remains open.
const List<String> _guestAuthRequiredPrefixes = [
  RoutePaths.checkout, // /checkout (+ /payment, /payment/otp)
  RoutePaths.orderSuccess, // /order-success
  RoutePaths.orders, // /orders (+ details, tracking)
  RoutePaths.makePayment, // /make-payment
  RoutePaths.paymentSuccess, // /payment-success
  RoutePaths.addresses, // /addresses (+ new)
  RoutePaths.kyc, // /kyc (+ details)
  '/verification', // all KYC steps
  RoutePaths.returns, // /returns (+ new)
  RoutePaths.rewards,
  RoutePaths.familyInfo,
];

/// Whether [loc] is a personal/transactional route a guest must sign in to open.
bool guestLocationRequiresAuth(String loc) {
  // Credit sub-screens are personal; the /credit dashboard tab stays open.
  if (loc.startsWith('${RoutePaths.creditDashboard}/')) return true;
  for (final prefix in _guestAuthRequiredPrefixes) {
    if (loc == prefix || loc.startsWith('$prefix/')) return true;
  }
  return false;
}

/// The verification flow (post-registration).
const Set<String> kVerificationLocations = {
  RoutePaths.kyc,
  RoutePaths.registrationSuccess,
  RoutePaths.identityVerification,
  RoutePaths.aadhaarVerification,
  RoutePaths.panVerification,
  RoutePaths.selfieVerification,
  RoutePaths.residenceVerification,
  RoutePaths.creditApplication,
  RoutePaths.verificationReview,
  RoutePaths.applicationSubmitted,
  RoutePaths.verificationStatus,
};

/// Routes a verification-pending/rejected user may still reach.
const Set<String> kRestrictedAllowed = {
  RoutePaths.verificationStatus,
  RoutePaths.applicationSubmitted,
  RoutePaths.support,
  RoutePaths.profile,
  RoutePaths.settings,
  RoutePaths.notifications,
};

/// Entry/auth screens an approved user should be redirected away from (to home).
/// NOTE: `/kyc` is intentionally NOT here — an approved user can open the KYC
/// flow on demand (e.g. from "Apply for Credit").
const Set<String> kEntryLocations = {
  RoutePaths.onboarding,
  RoutePaths.login,
  RoutePaths.otp,
  RoutePaths.register,
};

/// Resolves the redirect target for an authenticated user at [loc], or null to
/// allow. Unauthenticated handling lives in the router (needs onboarding state).
String? resolveGuardRedirect(UserStage stage, String loc) {
  switch (stage) {
    case UserStage.unauthenticated:
      return null;
    case UserStage.registrationIncomplete:
      return loc == RoutePaths.register ? null : RoutePaths.register;
    // KYC is optional — these stages no longer gate the app; treat them as full
    // access (KYC is reachable on demand and gated only inside credit screens).
    case UserStage.verificationNotStarted:
    case UserStage.verificationPending:
    case UserStage.verificationRejected:
    case UserStage.approved:
      return kEntryLocations.contains(loc) ? RoutePaths.home : null;
  }
}

/// The post-splash landing route for a given [stage].
String landingForStage(UserStage stage) => switch (stage) {
      UserStage.unauthenticated => RoutePaths.login,
      UserStage.registrationIncomplete => RoutePaths.register,
      // Everyone else (incl. KYC-incomplete) lands on Home — KYC is optional.
      _ => RoutePaths.home,
    };
