/// Centralized route path strings. Use with [RouteNames] for named navigation
/// (`context.goNamed(RouteNames.home)`).
abstract final class RoutePaths {
  RoutePaths._();

  static const String splash = '/';
  static const String onboarding = '/onboarding';

  // Auth
  static const String login = '/login';
  static const String otp = '/otp';
  static const String register = '/register';
  static const String kyc = '/kyc';

  // Verification flow (full-screen)
  static const String identityVerification = '/verification/identity';
  static const String selfieVerification = '/verification/selfie';
  static const String creditApplication = '/verification/credit';
  static const String verificationReview = '/verification/review';
  static const String applicationSubmitted = '/verification/submitted';
  static const String verificationStatus = '/verification/status';

  // Shell / main tabs
  static const String home = '/home';
  static const String categories = '/categories';
  static const String cart = '/cart';
  static const String account = '/account';

  // Catalog (sub-routes off home)
  static const String subCategories = '/categories/:categoryId';
  static const String products = '/products';
  static const String productDetails = '/products/:productId';
  static const String search = '/search';
  static const String offers = '/offers';
  static const String wishlist = '/wishlist';

  // Product sections
  static const String popularProducts = '/products/popular';
  static const String recommendedProducts = '/products/recommended';
  static const String recentlyOrdered = '/products/recently-ordered';
  static const String salesProducts = '/products/sales';

  // Checkout
  static const String checkout = '/checkout';
  static const String payment = '/checkout/payment';
  static const String orderSuccess = '/order-success';

  // Orders
  static const String orders = '/orders';
  static const String orderDetails = '/orders/:orderId';
  static const String orderTracking = '/orders/:orderId/tracking';

  // Credit / billing
  static const String creditDashboard = '/credit';
  static const String statements = '/credit/statements';
  static const String statementDetail = '/credit/statements/:id';
  static const String invoices = '/credit/invoices';
  static const String invoiceDetail = '/credit/invoices/:id';
  static const String paymentHistory = '/credit/history';
  static const String collections = '/credit/collections';
  static const String repayment = '/credit/repay';
  static const String repaymentSuccess = '/credit/repay/success';
  // Legacy credit-feature routes (retained for the original credit screens).
  static const String weeklyBill = '/credit/weekly';
  static const String monthlyBill = '/credit/monthly';
  static const String creditScore = '/credit/score';
  static const String makePayment = '/make-payment';
  static const String paymentSuccess = '/payment-success';

  // Profile / settings
  static const String profile = '/profile';
  static const String addresses = '/addresses';
  static const String addAddress = '/addresses/new';
  static const String notifications = '/notifications';
  static const String settings = '/settings';
  static const String support = '/support';

  // Secondary screens (legal, settings sub-pages, support, engagement)
  static const String privacyPolicy = '/privacy-policy';
  static const String terms = '/terms';
  static const String about = '/about';
  static const String faq = '/support/faq';
  static const String raiseTicket = '/support/new-ticket';
  static const String tickets = '/support/tickets';
  static const String ticketDetails = '/support/tickets/detail';
  static const String supportChat = '/support/chat';
  static const String language = '/settings/language';
  static const String notificationSettings = '/settings/notification-prefs';
  static const String securitySettings = '/settings/security';
  static const String referEarn = '/refer';
  static const String coupons = '/offers/coupons';
  static const String todaysDeals = '/offers/deals';
  static const String outstandingDue = '/credit/outstanding';
  static const String paymentReminders = '/notifications/reminders';
  static const String familyInfo = '/family';
  static const String kycDetails = '/kyc/details';
  static const String residenceVerification = '/verification/residence';
  static const String registrationSuccess = '/register/success';
  static const String aadhaarVerification = '/verification/aadhaar';
  static const String panVerification = '/verification/pan';
  static const String cashCollectionRequest = '/credit/collections/request';
  // Phase 3 — customer engagement modules
  static const String rewards = '/rewards';
  static const String subscriptions = '/subscriptions';
  static const String returns = '/returns';
  static const String requestReturn = '/returns/new';
  static const String contact = '/contact';
  static const String careers = '/careers';
  // Serviceability
  static const String notServiceable = '/not-serviceable';

  // Helpers for parameterized paths.
  static String subCategoriesOf(String categoryId) => '/categories/$categoryId';
  static String productDetailsOf(String productId) => '/products/$productId';
  static String orderDetailsOf(String orderId) => '/orders/$orderId';
  static String orderTrackingOf(String orderId) => '/orders/$orderId/tracking';
}

/// Named-route identifiers (decoupled from paths).
abstract final class RouteNames {
  RouteNames._();

  static const String splash = 'splash';
  static const String onboarding = 'onboarding';
  static const String login = 'login';
  static const String otp = 'otp';
  static const String register = 'register';
  static const String kyc = 'kyc';
  static const String identityVerification = 'identityVerification';
  static const String selfieVerification = 'selfieVerification';
  static const String creditApplication = 'creditApplication';
  static const String verificationReview = 'verificationReview';
  static const String applicationSubmitted = 'applicationSubmitted';
  static const String verificationStatus = 'verificationStatus';

  static const String home = 'home';
  static const String categories = 'categories';
  static const String cart = 'cart';
  static const String account = 'account';

  static const String subCategories = 'subCategories';
  static const String products = 'products';
  static const String productDetails = 'productDetails';
  static const String search = 'search';
  static const String offers = 'offers';
  static const String wishlist = 'wishlist';

  static const String popularProducts = 'popularProducts';
  static const String recommendedProducts = 'recommendedProducts';
  static const String recentlyOrdered = 'recentlyOrdered';
  static const String salesProducts = 'salesProducts';

  static const String checkout = 'checkout';
  static const String payment = 'payment';
  static const String orderSuccess = 'orderSuccess';

  static const String orders = 'orders';
  static const String orderDetails = 'orderDetails';
  static const String orderTracking = 'orderTracking';

  static const String creditDashboard = 'creditDashboard';
  static const String statements = 'statements';
  static const String statementDetail = 'statementDetail';
  static const String invoices = 'invoices';
  static const String invoiceDetail = 'invoiceDetail';
  static const String paymentHistory = 'paymentHistory';
  static const String collections = 'collections';
  static const String repayment = 'repayment';
  static const String repaymentSuccess = 'repaymentSuccess';
  static const String weeklyBill = 'weeklyBill';
  static const String monthlyBill = 'monthlyBill';
  static const String creditScore = 'creditScore';
  static const String makePayment = 'makePayment';
  static const String paymentSuccess = 'paymentSuccess';

  static const String profile = 'profile';
  static const String addresses = 'addresses';
  static const String addAddress = 'addAddress';
  static const String notifications = 'notifications';
  static const String settings = 'settings';
  static const String support = 'support';

  static const String privacyPolicy = 'privacyPolicy';
  static const String terms = 'terms';
  static const String about = 'about';
  static const String faq = 'faq';
  static const String raiseTicket = 'raiseTicket';
  static const String tickets = 'tickets';
  static const String ticketDetails = 'ticketDetails';
  static const String supportChat = 'supportChat';
  static const String language = 'language';
  static const String notificationSettings = 'notificationSettings';
  static const String securitySettings = 'securitySettings';
  static const String referEarn = 'referEarn';
  static const String coupons = 'coupons';
  static const String todaysDeals = 'todaysDeals';
  static const String outstandingDue = 'outstandingDue';
  static const String paymentReminders = 'paymentReminders';
  static const String familyInfo = 'familyInfo';
  static const String kycDetails = 'kycDetails';
  static const String residenceVerification = 'residenceVerification';
  static const String registrationSuccess = 'registrationSuccess';
  static const String aadhaarVerification = 'aadhaarVerification';
  static const String panVerification = 'panVerification';
  static const String cashCollectionRequest = 'cashCollectionRequest';
  // Phase 3 — customer engagement modules
  static const String rewards = 'rewards';
  static const String subscriptions = 'subscriptions';
  static const String returns = 'returns';
  static const String requestReturn = 'requestReturn';
  static const String contact = 'contact';
  static const String careers = 'careers';
  static const String notServiceable = 'notServiceable';
}
