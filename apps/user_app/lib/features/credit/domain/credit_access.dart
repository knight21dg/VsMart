import '../../auth/domain/entities/user.dart';

/// Single source of truth for whether a customer may see / use VS Credit.
///
/// VS Credit is opt-in: a customer must apply (KYC) and be approved before any
/// credit surface — balances, dashboards, the pay-on-credit option — is shown.
/// Everywhere credit UI could appear, gate it on this so nothing leaks to a
/// customer who hasn't applied.
enum CreditAccess {
  /// Never applied — show a clean "Apply for VS Credit" prompt only.
  notApplied,

  /// Applied, awaiting approval — show an "under review" state.
  pending,

  /// Approved & active — full credit UI is allowed.
  active,

  /// Application was rejected — show a "re-apply" state.
  rejected,
}

extension CreditAccessX on CreditAccess {
  /// True only when the customer may see real credit figures / pay on credit.
  bool get isActive => this == CreditAccess.active;

  /// True when there is nothing to show but an apply / re-apply / pending CTA.
  bool get isLocked => this != CreditAccess.active;
}

/// Derive the [CreditAccess] for [user]. The `creditEnabled` flag (set on KYC
/// approval) is authoritative; KYC status drives the pending / rejected copy.
CreditAccess creditAccessForUser(User? user) {
  if (user == null) return CreditAccess.notApplied;
  if (user.creditEnabled) return CreditAccess.active;
  return switch (user.kycStatus) {
    KycStatus.verified => CreditAccess.active, // approved but flag not synced yet
    KycStatus.pending => CreditAccess.pending,
    KycStatus.rejected => CreditAccess.rejected,
    KycStatus.notStarted => CreditAccess.notApplied,
  };
}
