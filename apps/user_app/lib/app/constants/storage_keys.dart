/// Keys used for Hive boxes, secure storage, and shared preferences.
abstract final class StorageKeys {
  StorageKeys._();

  // ----- Hive box names -----
  static const String userBox = 'vs_user_box';
  static const String cartBox = 'vs_cart_box';
  static const String cacheBox = 'vs_cache_box';
  static const String settingsBox = 'vs_settings_box';
  static const String verificationBox = 'vs_verification_box';
  static const String addressBox = 'vs_address_box';
  // Commerce cache boxes
  static const String categoryBox = 'vs_category_box';
  static const String subCategoryBox = 'vs_subcategory_box';
  static const String productBox = 'vs_product_box';
  static const String offerBox = 'vs_offer_box';
  static const String recentlyViewedBox = 'vs_recently_viewed_box';
  // Orders
  static const String orderBox = 'vs_order_box';
  static const String orderDraftBox = 'vs_order_draft_box';
  static const String trackingBox = 'vs_tracking_box';
  static const String checkoutDraftBox = 'vs_checkout_draft_box';
  // Credit billing
  static const String creditLedgerBox = 'vs_credit_ledger_box';
  static const String billingCycleBox = 'vs_billing_cycle_box';
  static const String statementBox = 'vs_statement_box';
  static const String invoiceBox = 'vs_invoice_box';
  static const String paymentHistoryBox = 'vs_payment_history_box';
  static const String collectionBox = 'vs_collection_box';

  // ----- Secure storage keys -----
  static const String accessToken = 'vs_access_token';
  static const String refreshToken = 'vs_refresh_token';
  static const String tokenExpiry = 'vs_token_expiry';

  // ----- User box keys -----
  static const String currentUser = 'current_user';
  static const String isLoggedIn = 'is_logged_in';

  // ----- Cart box keys -----
  static const String cartItems = 'cart_items';

  // ----- Verification box keys (offline drafts) -----
  static const String verificationDraft = 'verification_draft';
  static const String creditApplicationDraft = 'credit_application_draft';

  // ----- Address box keys -----
  static const String addresses = 'addresses';

  // ----- Settings keys -----
  static const String themeMode = 'theme_mode';
  static const String locale = 'locale';
  static const String onboardingSeen = 'onboarding_seen';
  static const String guestMode = 'guest_mode';
  static const String notificationsEnabled = 'notifications_enabled';
  static const String recentSearches = 'recent_searches';

  // ----- Wishlist box -----
  static const String wishlistBox = 'vs_wishlist_box';
  static const String wishlistItems = 'wishlist_items';
}
