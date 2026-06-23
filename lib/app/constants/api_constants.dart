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

  // ----- KYC -----
  static const String kycSubmit = '/kyc/submit';
  static const String kycStatus = '/kyc/status';
  static String kycDocumentUrl(String id) => '/kyc/documents/$id/url';

  // ----- User / profile -----
  static const String me = '/users/me';
  static const String updateProfile = '/users/me';

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
  static const String cart = '/cart';
  static const String cartQuote = '/cart/quote';
  static const String cartItems = '/cart/items';
  static String cartItem(String id) => '/cart/items/$id';

  // ----- Checkout / orders -----
  static const String checkout = '/checkout';
  static const String orders = '/orders';
  static String orderDetails(String id) => '/orders/$id';
  static String orderTracking(String id) => '/orders/$id/tracking';
  static String orderInvoice(String id) => '/orders/$id/invoice';

  // ----- Credit -----
  static const String creditDashboard = '/credit/dashboard';
  static const String creditScore = '/credit/score';
  static const String creditLedger = '/credit/ledger';
  static const String creditRepay = '/credit/repay';
  static const String creditCashCollection = '/credit/cash-collection';
  static const String creditStatements = '/credit/statements';
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

  // ----- Subscriptions -----
  static const String subscriptions = '/subscriptions';
  static String subscription(String id) => '/subscriptions/$id';
}
