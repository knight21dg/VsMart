/// Typed references to bundled assets. Keeps asset paths in one place so
/// renames are a single-line change and typos fail fast.
abstract final class AssetConstants {
  AssetConstants._();

  static const String _images = 'assets/images';
  static const String _icons = 'assets/icons';
  static const String _illustrations = 'assets/illustrations';
  static const String _animations = 'assets/animations';

  // Images
  static const String logo = '$_images/vsmartlogo.png';
  static const String logoWhite = '$_images/vsmartlogo.png';
  static const String placeholderProduct = '$_images/vsmartlogo.png';

  // Icons
  static const String googleIcon = '$_icons/google.svg';

  // Illustrations (onboarding / empty states)
  static const String otpVerification = '$_illustrations/otp_verification.svg';
  static const String onboarding1 = '$_illustrations/onboarding_1.png';
  static const String onboarding2 = '$_illustrations/onboarding_2.png';
  static const String onboarding3 = '$_illustrations/onboarding_3.png';
  static const String emptyCart = '$_illustrations/empty_cart.png';
  static const String emptyOrders = '$_illustrations/empty_orders.png';
  static const String emptySearch = '$_illustrations/empty_search.png';
  static const String errorState = '$_illustrations/error_state.png';

  // Animations (Lottie)
  static const String loading = '$_animations/loading.json';
  static const String success = '$_animations/success.json';
  static const String orderPlaced = '$_animations/order_placed.json';
}
