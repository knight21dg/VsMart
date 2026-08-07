/// REST API endpoint paths for the VS Mart backend.
///
/// Base URLs live in [AppConfig]; these are relative paths appended to it.
abstract final class ApiConstants {
  ApiConstants._();

  // ----- Auth -----
  static const String sendOtp = '/auth/otp/send';
  static const String verifyOtp = '/auth/otp/verify';
  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String refreshToken = '/auth/refresh';
  static const String logout = '/auth/logout';
  // Public, compliant account-deletion REQUEST (reviewed + processed by ops —
  // not an instant delete). Body per backend DeletionRequestSerializer.
  static const String accountDeletionRequest = '/account/deletion-request';

  // ----- KYC -----
  static const String kycSubmit = '/kyc/submit';
  static const String kycStatus = '/kyc/status';
  static const String kycRetry = '/kyc/retry';
  static String kycDocumentUrl(String id) => '/kyc/documents/$id/url';
  // API verification (gov-source, server-side only — the app never calls a
  // verification provider directly).
  static const String kycCreditSendOtp = '/kyc/credit/send-otp';
  static const String kycCreditCheck = '/kyc/credit/check';
  static const String kycCreditSubmit = '/kyc/credit/submit';
  static const String kycPanVerify = '/kyc/pan/verify';
  static const String kycAadhaarSendOtp = '/kyc/aadhaar/send-otp';
  static const String kycAadhaarVerifyOtp = '/kyc/aadhaar/verify-otp';
  static const String kycBankVerify = '/kyc/bank/verify';

  // ----- User / profile -----
  static const String me = '/users/me';
  static const String updateProfile = '/users/me';
  static const String avatarUpload = '/users/me/avatar';

  // ----- Addresses -----
  static const String addresses = '/addresses';
  static String address(String id) => '/addresses/$id';

  // ----- Catalog -----
  static const String categories = '/categories';
  static String subCategories(String categoryId) =>
      '/categories/$categoryId/sub-categories';
  static const String products = '/products';
  static String productDetails(String id) => '/products/$id';
  static const String search = '/products/search';

  // ----- Offers -----
  static const String offers = '/offers';

  // ----- Wishlist -----
  static const String wishlist = '/wishlist';
  static String wishlistItem(String productId) => '/wishlist/$productId';

  // ----- Cart -----
  // The local (Hive) cart is the customer's working basket; it is pushed to the
  // server as a whole via `PUT /cart` at checkout. The per-line /cart/items
  // endpoints are deliberately unused by this client — see
  // `OrderRemoteDataSource._syncCart` for why line-by-line syncing was unsafe.
  static const String cart = '/cart';
  static const String cartQuote = '/cart/quote';
  static const String cartValidate = '/cart/validate';

  // ----- Checkout / orders -----
  static const String checkout = '/checkout';
  static const String orders = '/orders';
  static String orderDetails(String id) => '/orders/$id';
  static String orderTracking(String id) => '/orders/$id/tracking';
  static String orderInvoice(String id) => '/orders/$id/invoice';

  /// What a reorder WOULD add — live prices, the original pack, and which lines
  /// are no longer available. Read-only.
  ///
  /// The sibling `POST /orders/<code>/reorder` is deliberately NOT used by this
  /// app: it mutates the SERVER cart, and this client's cart is local (Hive) and
  /// pushed wholesale via `PUT /cart` at checkout — which would erase whatever the
  /// server-side reorder had added. We take the preview's authoritative data and
  /// build the local cart from it.
  static String orderReorderPreview(String id) => '/orders/$id/reorder/preview';

  /// Branded PDF receipt for a completed payment (credit repayments included).
  static String paymentReceipt(String id) => '/payments/$id/receipt';
  /// Per-ORDER feedback (VS Mart shows no product ratings — groceries don't need
  /// them; how the delivery went is what matters).
  static String orderFeedback(String id) => '/orders/$id/feedback';

  // ----- Collections (customer-facing) -----
  static const String collectionConfirm = '/collections/confirm';

  // ----- Credit -----
  static const String creditDashboard = '/credit/dashboard';
  // Credit application: apply -> admin review -> limit granted.
  static const String creditApply = '/credit/apply';
  static const String creditApplication = '/credit/application';
  static const String creditApplicationWithdraw = '/credit/application/withdraw';
  static const String creditScore = '/credit/score';
  static const String creditCibil = '/credit/cibil';
  static const String creditCibilCheck = '/credit/cibil/check';
  static const String creditLedger = '/credit/ledger';
  static const String creditRepay = '/credit/repay';
  static const String creditCashCollection = '/credit/cash-collection';
  static const String creditStatements = '/credit/statements';
  static String creditStatementPdf(String id) => '/credit/statements/$id/pdf';
  static const String creditOutstanding = '/credit/outstanding';
  static const String weeklyBill = '/credit/bills/weekly';
  static const String monthlyBill = '/credit/bills/monthly';
  static const String creditFamily = '/credit/family';
  static String creditFamilyMember(String id) => '/credit/family/members/$id';

  // ----- Payments -----
  static const String payments = '/payments';
  static const String paymentHistory = '/payments/history';
  static String paymentDetail(String id) => '/payments/$id';

  // ----- Billing -----
  static const String billingInvoices = '/billing/invoices';
  static const String billingReceipts = '/billing/receipts';
  static const String collectionsHistory = '/collections/history';

  // ----- Uploads -----
  static const String uploads = '/uploads';
  /// Authenticated media upload (multipart `file`) → returns variant URLs.
  static const String mediaUpload = '/media';

  // ----- Offers / coupons -----
  static const String couponsValidate = '/coupons/validate';
  static const String couponsWallet = '/coupons/wallet';

  // ----- Referrals -----
  static const String referrals = '/referrals';
  static const String referralsApply = '/referrals/apply';

  // ----- Notifications -----
  static const String notifications = '/notifications';
  static String notificationRead(String id) => '/notifications/$id/read';
  static const String notificationPreferences = '/notifications/preferences';
  static const String registerDeviceToken = '/notifications/device-token';

  // ----- Support -----
  static const String supportTickets = '/support/tickets';
  static const String supportFaqs = '/support/faqs';
  static const String supportContact = '/support/contact';

  // ----- Serviceability / zones -----
  static const String serviceabilityCheck = '/serviceability/check';
  static const String expansionRequest = '/serviceability/expansion-request';

  // ----- System (client bootstrap; all under /api/v1) -----
  static const String appConfig = '/app-config';
  static const String version = '/version';
  static const String maintenanceStatus = '/maintenance-status';
  static const String featureFlags = '/feature-flags';

  // ----- Content / CMS (public) -----
  static const String contentPages = '/content/pages';
  static String contentPage(String slug) => '/content/pages/$slug';

  // ----- Reviews -----
  static String productReviews(String productId) =>
      '/products/$productId/reviews';
  static const String myReviews = '/reviews/mine';

  // ----- Returns -----
  static const String returns = '/returns';
  static String orderReturns(String orderCode) => '/orders/$orderCode/returns';
  static String returnDetail(String code) => '/returns/$code';

  // ----- Loyalty -----
  static const String loyalty = '/loyalty';
  static const String loyaltyLedger = '/loyalty/ledger';
  static const String loyaltyRedeem = '/loyalty/redeem';

}
