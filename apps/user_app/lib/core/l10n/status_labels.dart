import '../../features/billing/domain/entities/billing_enums.dart';
import '../../features/orders/domain/entities/order_enums.dart';
import '../../features/verification/domain/entities/verification_enums.dart';
import '../../l10n/generated/app_localizations.dart';

/// Localized labels for domain enums / backend status strings.
///
/// The enum definitions stay context-free (their `.label` getters remain for
/// logging/fallback), but anything **shown to the customer** must be localized.
/// These extensions/functions take an [AppLocalizations] and are called from the
/// widgets that render status chips/timelines (where a BuildContext exists) — the
/// fix for the "labels live in no-context domain code" localization blocker.
extension OrderStatusL10n on OrderStatus {
  String labelL10n(AppLocalizations l) => switch (this) {
        OrderStatus.draft => l.orderStatusDraft,
        OrderStatus.pending => l.orderStatusPending,
        OrderStatus.placed => l.orderStatusPlaced,
        OrderStatus.confirmed => l.orderStatusConfirmed,
        OrderStatus.packed => l.orderStatusPacked,
        OrderStatus.readyForDispatch => l.orderStatusReadyForDispatch,
        OrderStatus.outForDelivery => l.orderStatusOutForDelivery,
        OrderStatus.delivered => l.orderStatusDelivered,
        OrderStatus.cancelled => l.orderStatusCancelled,
        OrderStatus.rejected => l.orderStatusRejected,
        OrderStatus.returned => l.orderStatusReturned,
        OrderStatus.partiallyReturned => l.orderStatusPartiallyReturned,
        OrderStatus.failedDelivery => l.orderStatusFailedDelivery,
      };
}

extension PaymentMethodL10n on PaymentMethod {
  String labelL10n(AppLocalizations l) => switch (this) {
        // "VS Credit" is a brand name → intentionally not translated.
        PaymentMethod.credit => 'VS Credit',
        PaymentMethod.cashOnDelivery => l.checkoutCod,
        PaymentMethod.upi => l.checkoutUpi,
        PaymentMethod.card => l.checkoutCard,
      };
}

extension PaymentStatusL10n on PaymentStatus {
  String labelL10n(AppLocalizations l) => switch (this) {
        PaymentStatus.pending => l.orderStatusPending,
        PaymentStatus.paid => l.payStatusPaid,
        PaymentStatus.failed => l.payStatusFailed,
        PaymentStatus.refunded => l.payStatusRefunded,
      };
}

extension VerificationStatusL10n on VerificationStatus {
  String labelL10n(AppLocalizations l) => switch (this) {
        VerificationStatus.notStarted => l.verifyStatusNotStarted,
        VerificationStatus.draft => l.verifyStatusDraft,
        VerificationStatus.pending => l.verifyStatusPending,
        VerificationStatus.underReview => l.verifyStatusUnderReview,
        VerificationStatus.approved => l.verifyStatusApproved,
        VerificationStatus.rejected => l.verifyStatusRejected,
      };
}

/// Localized label for a backend KYC status string
/// (`not_started` / `pending` / `verified` / `rejected`).
String kycStatusLabel(AppLocalizations l, String status) => switch (status) {
      'verified' || 'approved' => l.kycVerified,
      'pending' => l.kycPending,
      'rejected' => l.kycRejected,
      _ => l.kycNotStarted,
    };

/// Localized label for a KYC document type (`aadhaar`/`pan`/`selfie`/`residence`).
String kycDocLabel(AppLocalizations l, String type) => switch (type) {
      'aadhaar' => l.kycDocAadhaar,
      'pan' => l.kycDocPan,
      'selfie' => l.kycDocSelfie,
      'residence' => l.kycDocResidence,
      _ => type,
    };

// ── Billing / credit-ledger enums ────────────────────────
extension TransactionTypeL10n on TransactionType {
  String labelL10n(AppLocalizations l) => switch (this) {
        TransactionType.purchase => l.billingPurchase,
        TransactionType.repayment => l.creditRepayment,
        TransactionType.penalty => l.billingPenalty,
        TransactionType.adjustment => l.billingAdjustment,
        TransactionType.refund => l.billingRefund,
      };
}

extension TransactionStatusL10n on TransactionStatus {
  String labelL10n(AppLocalizations l) => switch (this) {
        TransactionStatus.pending => l.orderStatusPending,
        TransactionStatus.completed => l.billingCompleted,
        TransactionStatus.failed => l.payStatusFailed,
        TransactionStatus.reversed => l.billingReversed,
      };
}

extension InvoiceStatusL10n on InvoiceStatus {
  String labelL10n(AppLocalizations l) => switch (this) {
        InvoiceStatus.pending => l.orderStatusPending,
        InvoiceStatus.paid => l.payStatusPaid,
        InvoiceStatus.overdue => l.billingOverdue,
        InvoiceStatus.cancelled => l.orderStatusCancelled,
      };
}

extension RepaymentMethodL10n on RepaymentMethod {
  String labelL10n(AppLocalizations l) => switch (this) {
        RepaymentMethod.upi => l.checkoutUpi,
        RepaymentMethod.card => l.checkoutCard,
        RepaymentMethod.bankTransfer => l.billingBankTransfer,
        RepaymentMethod.cashCollection => l.billingCashCollection,
      };
}

extension CollectionStatusL10n on CollectionStatus {
  String labelL10n(AppLocalizations l) => switch (this) {
        CollectionStatus.pending => l.orderStatusPending,
        CollectionStatus.assigned => l.billingAssigned,
        CollectionStatus.collected => l.billingCollected,
        CollectionStatus.failed => l.payStatusFailed,
      };
}
