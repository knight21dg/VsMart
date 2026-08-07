import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/domain/entities/user.dart';
import '../../features/auth/presentation/providers/current_user_provider.dart';
import '../../features/auth/presentation/providers/session_provider.dart';
import '../../features/serviceability/presentation/providers/serviceability_gate_providers.dart';
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
  RoutePaths.checkout, // /checkout
  RoutePaths.orderSuccess, // /order-success
  RoutePaths.orders, // /orders (+ details, tracking)
  RoutePaths.addresses, // /addresses (+ new)
  RoutePaths.kyc, // /kyc (+ details)
  '/verification', // all KYC steps
  RoutePaths.returns, // /returns (+ new)
  RoutePaths.rewards,
  RoutePaths.familyInfo,
  RoutePaths.collectionConfirm, // /collection-confirm (view OTP to confirm cash)
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

/// Routes that stay reachable even when a genuinely out-of-area (unserviceable)
/// verdict funnels the customer to NotServiceableScreen. The whole verification
/// flow, support, and legal pages must stay open so an out-of-area user can still
/// get help or finish KYC. The lock screen itself is NOT in this set — it's
/// handled explicitly so a now-serviceable user is bounced off it back to Home.
const Set<String> _serviceabilityExemptLocations = {
  RoutePaths.support,
  RoutePaths.terms,
  RoutePaths.privacyPolicy,
  RoutePaths.orderSuccess,
};

bool _isServiceabilityExempt(String loc) {
  if (_serviceabilityExemptLocations.contains(loc)) return true;
  // Address management must stay open. The gate's whole remedy is "change your
  // location", which means adding or picking an address — locking those behind it
  // is circular. It also destroyed a half-filled add-address form whenever the
  // verdict changed while the customer was typing.
  if (loc == RoutePaths.addresses || loc.startsWith('${RoutePaths.addresses}/')) {
    return true;
  }
  // The KYC / verification flow is part of onboarding and must never be locked.
  if (kVerificationLocations.contains(loc)) return true;
  if (loc.startsWith('/verification')) return true;
  if (loc == RoutePaths.kyc || loc.startsWith('${RoutePaths.kyc}/')) return true;
  // Order-related screens must stay reachable after a successful checkout so the
  // customer can view their confirmation, track, and browse order history.
  if (loc == RoutePaths.orders || loc.startsWith('${RoutePaths.orders}/')) {
    return true;
  }
  return false;
}

/// Composes the two authenticated-user gates in the exact order the router
/// applies them: the verification lifecycle guard first, then the serviceability
/// hard-lock. Returns the redirect target for [loc], or null to allow it.
///
/// The serviceability lock only engages once registration is complete
/// ([UserStage.approved]). Engaging it earlier ping-pongs a still-registering,
/// out-of-area user forever: the lifecycle guard pins them to `/register`, the
/// serviceability gate then bounces `/register` → `/not-serviceable`, and the
/// lifecycle guard bounces `/not-serviceable` → `/register` … a redirect loop
/// go_router resolves by throwing, landing the customer on the "Route not found"
/// error page instead of the sign-up screen.
String? resolveAuthenticatedRedirect(UserStage stage, GateStatus gate, String loc) {
  final lifecycle = resolveGuardRedirect(stage, loc);
  if (lifecycle != null) return lifecycle;
  if (stage != UserStage.approved) return null;
  return serviceabilityGateRedirect(gate, loc);
}

/// Resolves the serviceability redirect for an authenticated user at [loc], or
/// null to allow. This is a SOFT gate on the GPS-based verdict — it never bricks
/// the whole app; it only funnels a *genuinely out-of-area* customer to the
/// lead-capture lock screen:
///
///  • [GateStatus.serviceable]        → allow; bounce off the lock screen to home.
///  • [GateStatus.unserviceable]      → route to NotServiceableScreen (the only
///    verdict that funnels there) so the customer can change location or register
///    expansion interest, instead of being bounced to Home. Exempt routes still
///    pass, and ordering is additionally gated server-side at checkout.
///  • [GateStatus.locationUnavailable] → fail OPEN: coverage couldn't be confirmed
///    (GPS denied / flaky), so keep browsing soft and just open the app.
///  • resolving (unresolved/checking) → hold on the lock screen, which renders a
///    "Checking your area…" loader instead of flashing main content.
///
/// Exempt routes (verification flow, support, legal) always pass.
String? serviceabilityGateRedirect(GateStatus gate, String loc) {
  final onLockScreen = loc == RoutePaths.notServiceable;

  // Still resolving the FIRST verdict (fresh install, no cached location): hold
  // briefly on the "checking your area" screen so we don't flash Home and then a
  // banner. Returning, previously-serviceable users skip this entirely — their
  // gate hydrates to `serviceable` from the persisted verdict.
  if (gate.isResolving) {
    if (onLockScreen || _isServiceabilityExempt(loc)) return null;
    return RoutePaths.notServiceable;
  }

  // Positively resolved OUT-OF-AREA (GPS put the customer outside every serving
  // zone): funnel them to NotServiceableScreen so the real change-location +
  // "notify me when you're here" lead-capture actually shows, rather than
  // bouncing to Home. This is scoped to the genuinely-unserviceable verdict — a
  // transient locationUnavailable/unresolved never lands here — and the exempt
  // routes (verification, support, legal) still pass through.
  if (gate == GateStatus.unserviceable) {
    if (onLockScreen || _isServiceabilityExempt(loc)) return null;
    return RoutePaths.notServiceable;
  }

  // Serviceable, or a transient locationUnavailable → fail OPEN: browsing stays
  // free (the Home banner tells the customer if we're not there yet) and ordering
  // is gated server-side at checkout. Bounce off the lock screen to Home; allow
  // everything else.
  return onLockScreen ? RoutePaths.home : null;
}
