/// Global, non-secret application constants for VS Mart.
abstract final class AppConstants {
  AppConstants._();

  static const String appName = 'VS Mart';
  static const String appTagline = 'Groceries on Credit, Simplified';
  static const String supportEmail = 'support@vsmart.app';
  static const String supportPhone = '+910000000000';

  /// Installed app version (keep in sync with pubspec `version:`). Compared
  /// against the backend `minAppVersion` to gate force-update.
  static const String appVersion = '1.0.0';

  // Pagination
  static const int defaultPageSize = 20;
  static const int firstPage = 1;

  // Timeouts (ms)
  static const int connectTimeout = 20000;
  static const int receiveTimeout = 20000;
  static const int sendTimeout = 20000;

  // OTP
  static const int otpLength = 6;
  static const int otpResendSeconds = 30;

  // Phone
  static const int phoneNumberLength = 10;
  static const String defaultCountryCode = '+91';
  static const String defaultCurrencySymbol = '₹';
  static const String defaultCurrencyCode = 'INR';

  // Cart / credit
  static const int maxCartItemQuantity = 99;

  // Animation durations
  static const Duration shortAnim = Duration(milliseconds: 200);
  static const Duration mediumAnim = Duration(milliseconds: 350);
  static const Duration longAnim = Duration(milliseconds: 600);
  static const Duration splashDuration = Duration(milliseconds: 700);

  // Debounce
  static const Duration searchDebounce = Duration(milliseconds: 400);
}
