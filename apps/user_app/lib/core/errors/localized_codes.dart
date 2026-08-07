import '../../l10n/generated/app_localizations.dart';

/// A localized (title, message) pair for a backend response code.
class LocalizedCode {
  const LocalizedCode(this.title, this.message);
  final String title;
  final String message;
}

/// Maps a backend response CODE to a localized title/message for the active
/// locale. Returns null when the code has no app translation yet — callers then
/// fall back to the backend's (English) title/message.
///
/// This is the bridge that keeps the **backend language-neutral** (it returns
/// only stable codes) while the **app owns the display language**: add a code
/// here + its keys in the ARB files and every surface that shows it localizes.
LocalizedCode? localizedForCode(AppLocalizations l, String? code) {
  switch (code) {
    case 'OUTSIDE_SERVICE_AREA':
      return LocalizedCode(
          l.codeOutsideServiceAreaTitle, l.codeOutsideServiceAreaBody);
    case 'STORE_CLOSED':
      return LocalizedCode(l.codeStoreClosedTitle, l.codeStoreClosedBody);
    case 'DELIVERY_CAPACITY_REACHED':
      return LocalizedCode(l.codeCapacityReachedTitle, l.codeCapacityReachedBody);
    case 'STORE_CHANGED':
      return LocalizedCode(l.codeStoreChangedTitle, l.codeStoreChangedBody);
    case 'PRODUCT_UNAVAILABLE':
      return LocalizedCode(
          l.codeProductUnavailableTitle, l.codeProductUnavailableBody);
    case 'OUT_OF_STOCK':
    case 'INSUFFICIENT_QUANTITY':
      return LocalizedCode(l.codeOutOfStockTitle, l.codeOutOfStockBody);
    case 'KYC_REQUIRED':
    case 'KYC_NOT_STARTED':
      return LocalizedCode(l.codeKycRequiredTitle, l.codeKycRequiredBody);
    case 'CREDIT_DISABLED':
    case 'CREDIT_FROZEN':
      return LocalizedCode(l.codeCreditDisabledTitle, l.codeCreditDisabledBody);
    case 'LIMIT_EXCEEDED':
      return LocalizedCode(l.codeLimitExceededTitle, l.codeLimitExceededBody);
    case 'OVERDUE_PAYMENT':
      return LocalizedCode(l.codeOverduePaymentTitle, l.codeOverduePaymentBody);
    case 'SESSION_EXPIRED':
    case 'TOKEN_EXPIRED':
      return LocalizedCode(l.codeSessionExpiredTitle, l.codeSessionExpiredBody);
    default:
      return null;
  }
}
