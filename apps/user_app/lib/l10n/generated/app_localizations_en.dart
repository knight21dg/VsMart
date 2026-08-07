// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTagline => 'Groceries in minutes';

  @override
  String get commonOk => 'OK';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonClose => 'Close';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonApply => 'Apply';

  @override
  String get commonSave => 'Save';

  @override
  String get commonContinue => 'Continue';

  @override
  String get commonNext => 'Next';

  @override
  String get commonBack => 'Back';

  @override
  String get commonDone => 'Done';

  @override
  String get commonYes => 'Yes';

  @override
  String get commonNo => 'No';

  @override
  String get commonSearch => 'Search';

  @override
  String get commonSeeAll => 'See all';

  @override
  String get commonLoading => 'Loading…';

  @override
  String get commonSomethingWentWrong => 'Something went wrong';

  @override
  String get commonNoInternet => 'No internet connection';

  @override
  String get commonTryAgain => 'Please try again';

  @override
  String get navHome => 'Home';

  @override
  String get navCategories => 'Categories';

  @override
  String get navCart => 'Cart';

  @override
  String get navOrders => 'Orders';

  @override
  String get navAccount => 'Account';

  @override
  String get navCredit => 'VS Credit';

  @override
  String get homeSearchHint => 'Search for groceries, brands and more';

  @override
  String get homeDeliverTo => 'Deliver to';

  @override
  String get homeOffersForYou => 'Offers for you';

  @override
  String get homeRecommended => 'Recommended for you';

  @override
  String get homePopular => 'Popular near you';

  @override
  String get homeShopByCategory => 'Shop by category';

  @override
  String serviceDeliveringIn(int minutes) {
    return 'Delivery in $minutes min';
  }

  @override
  String serviceFrom(String store) {
    return 'from $store';
  }

  @override
  String get serviceNotAvailableTitle =>
      'We are not available in your area yet';

  @override
  String get serviceNotAvailableBody =>
      'VS Mart doesn\'t deliver to this location right now. Tell us where you are and we\'ll notify you when we launch.';

  @override
  String get serviceChangeLocation => 'Change location';

  @override
  String get serviceNotifyMe => 'Notify me';

  @override
  String get serviceStoreClosed => 'Store currently closed';

  @override
  String serviceStoreClosedResumesAt(String time) {
    return 'Store is closed. Orders resume at $time.';
  }

  @override
  String get serviceSlotsFull => 'Today\'s delivery slots are full';

  @override
  String get productAddToCart => 'Add to cart';

  @override
  String get productAdded => 'Added';

  @override
  String get productOutOfStock => 'Out of stock';

  @override
  String get productInCart => 'In cart';

  @override
  String productSave(String amount) {
    return 'Save $amount';
  }

  @override
  String get cartTitle => 'My cart';

  @override
  String get cartEmptyTitle => 'Your cart is empty';

  @override
  String get cartEmptyBody => 'Add items to get started';

  @override
  String get cartSubtotal => 'Subtotal';

  @override
  String get cartDeliveryFee => 'Delivery fee';

  @override
  String get cartGst => 'GST';

  @override
  String get cartTotal => 'Total';

  @override
  String get cartFree => 'FREE';

  @override
  String cartItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
      zero: 'No items',
    );
    return '$_temp0';
  }

  @override
  String get cartProceedToCheckout => 'Proceed to checkout';

  @override
  String get checkoutTitle => 'Checkout';

  @override
  String get checkoutDeliveryAddress => 'Delivery address';

  @override
  String get checkoutPaymentMethod => 'Payment method';

  @override
  String get checkoutPlaceOrder => 'Place order';

  @override
  String get checkoutPayNow => 'Pay now';

  @override
  String get checkoutCod => 'Cash on delivery';

  @override
  String get checkoutUpi => 'UPI';

  @override
  String get checkoutCard => 'Card';

  @override
  String get checkoutVsCredit => 'VS Credit';

  @override
  String get checkoutOrderPlacedTitle => 'Order placed!';

  @override
  String checkoutOrderPlacedBody(String code) {
    return 'Your order $code has been placed.';
  }

  @override
  String get creditTitle => 'VS Credit';

  @override
  String get creditLimit => 'Credit limit';

  @override
  String get creditAvailable => 'Available credit';

  @override
  String get creditOutstanding => 'Outstanding';

  @override
  String creditOutstandingAmount(String amount) {
    return 'You have $amount outstanding';
  }

  @override
  String creditDueOn(String date) {
    return 'Due on $date';
  }

  @override
  String get creditRepay => 'Repay';

  @override
  String get creditRepayNow => 'Repay now';

  @override
  String get creditPayBill => 'Pay bill';

  @override
  String get creditFrozen => 'Your credit is temporarily frozen';

  @override
  String get creditCompleteKyc => 'Complete KYC to use VS Credit';

  @override
  String get kycTitle => 'Verification';

  @override
  String get kycCompleteTitle => 'Complete your KYC';

  @override
  String get kycPending => 'Verification in progress';

  @override
  String get kycVerified => 'Verified';

  @override
  String get kycRejected => 'Verification rejected';

  @override
  String get kycUploadDocument => 'Upload document';

  @override
  String get kycVerifyIdentity => 'Verify identity';

  @override
  String get ordersTitle => 'My orders';

  @override
  String get ordersEmpty => 'You have no orders yet';

  @override
  String get ordersTrack => 'Track order';

  @override
  String get reorderSheetTitle => 'Add these to your cart?';

  @override
  String reorderAddAll(int count) {
    return 'Add $count to cart';
  }

  @override
  String get reorderUnavailableHeading => 'Not available right now';

  @override
  String get reorderDiscontinued => 'No longer sold';

  @override
  String get reorderOutOfStock => 'Out of stock';

  @override
  String get reorderNothingAvailable =>
      'None of these items are available right now.';

  @override
  String get reorderPricesMayHaveChanged => 'Prices shown are today\'s.';

  @override
  String get ordersAmountPaid => 'Amount paid';

  @override
  String get ordersAmountRefunded => 'Refunded';

  @override
  String get ordersRefundPending => 'Refund not yet issued';

  @override
  String get deliveryOtpTitle => 'Delivery OTP';

  @override
  String get deliveryOtpShare => 'Share this code with your rider at the door';

  @override
  String get profileOrderArriving => 'Your order is arriving';

  @override
  String get profileShowOtp => 'Tap to track and view your delivery OTP';

  @override
  String get ordersReorder => 'Reorder';

  @override
  String get orderStatusPending => 'Pending';

  @override
  String get orderStatusConfirmed => 'Confirmed';

  @override
  String get orderStatusPacked => 'Packed';

  @override
  String get orderStatusOutForDelivery => 'Out for delivery';

  @override
  String get orderStatusDelivered => 'Delivered';

  @override
  String get orderStatusCancelled => 'Cancelled';

  @override
  String get accountTitle => 'Account';

  @override
  String get accountSettings => 'Settings';

  @override
  String get accountLanguage => 'Language';

  @override
  String get accountLogout => 'Log out';

  @override
  String get languageTitle => 'Language';

  @override
  String get languageSelect => 'Select language';

  @override
  String get languageCurrent => 'Current language';

  @override
  String get languageApply => 'Apply language';

  @override
  String get languageUpdated => 'Language updated';

  @override
  String get languagePreview => 'Language preview';

  @override
  String get codeOutsideServiceAreaTitle => 'Service unavailable';

  @override
  String get codeOutsideServiceAreaBody =>
      'VS Mart currently doesn\'t deliver to your location.';

  @override
  String get codeStoreClosedTitle => 'Store closed';

  @override
  String get codeStoreClosedBody =>
      'The store for your area isn\'t accepting orders right now.';

  @override
  String get codeCapacityReachedTitle => 'Delivery slots full';

  @override
  String get codeCapacityReachedBody =>
      'Today\'s delivery capacity for your area is full. Please try again tomorrow.';

  @override
  String get codeStoreChangedTitle => 'Delivery area changed';

  @override
  String get codeStoreChangedBody =>
      'Your delivery address moved to a different store\'s area, so your cart was refreshed.';

  @override
  String get codeProductUnavailableTitle => 'Not available at your store';

  @override
  String get codeProductUnavailableBody =>
      'Some items in your cart aren\'t carried by the store serving your area.';

  @override
  String get codeOutOfStockTitle => 'Item unavailable';

  @override
  String get codeOutOfStockBody =>
      'One or more items in your cart are out of stock.';

  @override
  String get codeKycRequiredTitle => 'Verification required';

  @override
  String get codeKycRequiredBody =>
      'Complete KYC before paying with VS Credit.';

  @override
  String get codeCreditDisabledTitle => 'Credit unavailable';

  @override
  String get codeCreditDisabledBody =>
      'VS Credit isn\'t available for this order.';

  @override
  String get codeLimitExceededTitle => 'Limit exceeded';

  @override
  String get codeLimitExceededBody =>
      'This order exceeds your available credit.';

  @override
  String get codeOverduePaymentTitle => 'Payment overdue';

  @override
  String get codeOverduePaymentBody =>
      'Clear your overdue dues before placing a new credit order.';

  @override
  String get codeSessionExpiredTitle => 'Session expired';

  @override
  String get codeSessionExpiredBody => 'Please sign in again to continue.';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonRemove => 'Remove';

  @override
  String get commonUpdate => 'Update';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonSubmit => 'Submit';

  @override
  String get commonShare => 'Share';

  @override
  String get commonViewDetails => 'View details';

  @override
  String get commonViewAll => 'View all';

  @override
  String get commonChange => 'Change';

  @override
  String get commonAdd => 'Add';

  @override
  String get commonProceed => 'Proceed';

  @override
  String get commonSkip => 'Skip';

  @override
  String get commonRefresh => 'Refresh';

  @override
  String get commonClearAll => 'Clear all';

  @override
  String get commonComingSoon => 'Coming soon';

  @override
  String get commonNoData => 'Nothing here yet';

  @override
  String get authWelcome => 'Welcome to VS Mart';

  @override
  String get authEnterPhone => 'Enter your mobile number';

  @override
  String get authPhoneHint => 'Mobile number';

  @override
  String get authSendOtp => 'Send OTP';

  @override
  String get authEnterOtp => 'Enter OTP';

  @override
  String authOtpSentTo(String phone) {
    return 'OTP sent to $phone';
  }

  @override
  String get authVerify => 'Verify';

  @override
  String get authResendOtp => 'Resend OTP';

  @override
  String authResendIn(int seconds) {
    return 'Resend in ${seconds}s';
  }

  @override
  String get authTermsAgree =>
      'By continuing you agree to our Terms & Privacy Policy';

  @override
  String get authLoginToContinue => 'Log in to continue';

  @override
  String get accountEditProfile => 'Edit profile';

  @override
  String get accountMyAddresses => 'My addresses';

  @override
  String get accountPaymentMethods => 'Payment methods';

  @override
  String get accountHelpSupport => 'Help & support';

  @override
  String get accountAboutUs => 'About us';

  @override
  String get accountTerms => 'Terms & conditions';

  @override
  String get accountPrivacy => 'Privacy policy';

  @override
  String get accountRateUs => 'Rate us';

  @override
  String get accountShareApp => 'Share app';

  @override
  String get accountDeleteAccount => 'Delete account';

  @override
  String accountVersion(String version) {
    return 'Version $version';
  }

  @override
  String get accountPersonalDetails => 'Personal details';

  @override
  String get accountName => 'Name';

  @override
  String get accountEmail => 'Email';

  @override
  String get accountPhone => 'Phone';

  @override
  String get accountSaveChanges => 'Save changes';

  @override
  String get orderDetailsTitle => 'Order details';

  @override
  String get orderId => 'Order ID';

  @override
  String orderPlacedOn(String date) {
    return 'Placed on $date';
  }

  @override
  String get orderItems => 'Items';

  @override
  String get orderBillDetails => 'Bill details';

  @override
  String get orderDownloadInvoice => 'Download invoice';

  @override
  String get orderNeedHelp => 'Need help?';

  @override
  String get orderCancel => 'Cancel order';

  @override
  String get orderRate => 'Rate order';

  @override
  String get orderSummary => 'Order summary';

  @override
  String get orderDeliveryDetails => 'Delivery details';

  @override
  String get orderItemTotal => 'Item total';

  @override
  String get orderGrandTotal => 'Grand total';

  @override
  String orderSaved(String amount) {
    return 'You saved $amount';
  }

  @override
  String get creditStatements => 'Statements';

  @override
  String get creditPaymentHistory => 'Payment history';

  @override
  String get creditRepayment => 'Repayment';

  @override
  String get creditDueDate => 'Due date';

  @override
  String get creditMinimumDue => 'Minimum due';

  @override
  String get creditTotalDue => 'Total due';

  @override
  String get creditTransactionHistory => 'Transaction history';

  @override
  String get creditScore => 'VS Score';

  @override
  String get creditUsed => 'Used';

  @override
  String get creditRepaymentPlan => 'Repayment plan';

  @override
  String get creditWeekend => 'Weekend';

  @override
  String get creditMonthEnd => 'Month end';

  @override
  String get creditPayFull => 'Pay full amount';

  @override
  String get creditNoDues => 'You have no dues';

  @override
  String get checkoutSelectAddress => 'Select delivery address';

  @override
  String get checkoutAddNewAddress => 'Add new address';

  @override
  String get checkoutApplyCoupon => 'Apply coupon';

  @override
  String get checkoutCouponApplied => 'Coupon applied';

  @override
  String get checkoutBillSummary => 'Bill summary';

  @override
  String get checkoutItemTotal => 'Item total';

  @override
  String get checkoutSavings => 'Savings';

  @override
  String get checkoutGrandTotal => 'Grand total';

  @override
  String get checkoutPaymentOptions => 'Payment options';

  @override
  String get checkoutDeliverySlot => 'Delivery slot';

  @override
  String get addressAdd => 'Add address';

  @override
  String get addressEdit => 'Edit address';

  @override
  String get addressFullName => 'Full name';

  @override
  String get addressPhone => 'Phone number';

  @override
  String get addressPincode => 'Pincode';

  @override
  String get addressHouseNo => 'House / flat no.';

  @override
  String get addressArea => 'Area / locality';

  @override
  String get addressLandmark => 'Landmark';

  @override
  String get addressCity => 'City';

  @override
  String get addressState => 'State';

  @override
  String get addressSave => 'Save address';

  @override
  String get addressSetDefault => 'Set as default';

  @override
  String get addressType => 'Address type';

  @override
  String get addressHome => 'Home';

  @override
  String get addressWork => 'Work';

  @override
  String get addressOther => 'Other';

  @override
  String get addressUseCurrentLocation => 'Use current location';

  @override
  String get addressNone => 'No saved addresses';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsMarkAllRead => 'Mark all as read';

  @override
  String get notificationsEmpty => 'No notifications yet';

  @override
  String get notificationsToday => 'Today';

  @override
  String get notificationsEarlier => 'Earlier';

  @override
  String get supportTitle => 'Help & support';

  @override
  String get supportContactUs => 'Contact us';

  @override
  String get supportFaqs => 'FAQs';

  @override
  String get supportRaiseTicket => 'Raise a ticket';

  @override
  String get supportMyTickets => 'My tickets';

  @override
  String get supportChat => 'Chat with us';

  @override
  String get supportCall => 'Call us';

  @override
  String get supportEmail => 'Email us';

  @override
  String get searchTitle => 'Search';

  @override
  String get searchHint => 'Search products';

  @override
  String get searchNoResults => 'No results found';

  @override
  String get searchRecent => 'Recent searches';

  @override
  String get searchPopular => 'Popular searches';

  @override
  String searchResultsFor(String query) {
    return 'Results for \"$query\"';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsDarkMode => 'Dark mode';

  @override
  String get settingsLightMode => 'Light mode';

  @override
  String get settingsSystemDefault => 'System default';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsPrivacy => 'Privacy & security';

  @override
  String get kycStartCta => 'Start verification';

  @override
  String get kycSubmitForReview => 'Submit for review';

  @override
  String get orderStatusDraft => 'Draft';

  @override
  String get orderStatusPlaced => 'Placed';

  @override
  String get orderStatusReadyForDispatch => 'Ready for dispatch';

  @override
  String get orderStatusRejected => 'Rejected';

  @override
  String get orderStatusReturned => 'Returned';

  @override
  String get orderStatusPartiallyReturned => 'Partially returned';

  @override
  String get orderStatusFailedDelivery => 'Delivery failed';

  @override
  String get payStatusPaid => 'Paid';

  @override
  String get payStatusFailed => 'Failed';

  @override
  String get payStatusRefunded => 'Refunded';

  @override
  String get verifyStatusNotStarted => 'Not started';

  @override
  String get verifyStatusDraft => 'Draft';

  @override
  String get verifyStatusPending => 'Pending';

  @override
  String get verifyStatusUnderReview => 'Under review';

  @override
  String get verifyStatusApproved => 'Approved';

  @override
  String get verifyStatusRejected => 'Rejected';

  @override
  String get kycNotStarted => 'Not started';

  @override
  String get kycDocAadhaar => 'Aadhaar Card';

  @override
  String get kycDocPan => 'PAN Card';

  @override
  String get kycDocSelfie => 'Selfie / Video KYC';

  @override
  String get kycDocResidence => 'Address proof';

  @override
  String get catalogAll => 'All';

  @override
  String get catalogApplyFilters => 'Apply filters';

  @override
  String get catalogBrand => 'Brand';

  @override
  String get catalogDescription => 'Description';

  @override
  String get catalogFilter => 'Filter';

  @override
  String get catalogFilters => 'Filters';

  @override
  String get catalogGoToCart => 'Go to cart';

  @override
  String get catalogInStock => 'In stock';

  @override
  String get catalogInStockOnly => 'In stock only';

  @override
  String get catalogMinDiscount => 'Minimum discount';

  @override
  String get catalogNoCategories => 'No categories found';

  @override
  String get catalogNoProducts => 'No products';

  @override
  String get catalogNoProductsFound => 'No products found';

  @override
  String get catalogPrice => 'Price';

  @override
  String get catalogProductDetails => 'Product details';

  @override
  String get catalogProducts => 'Products';

  @override
  String get catalogQuantity => 'Quantity';

  @override
  String get catalogSearchCategories => 'Search categories';

  @override
  String get catalogSelectVariation => 'Select variation';

  @override
  String get catalogSort => 'Sort';

  @override
  String get catalogSortBy => 'Sort by';

  @override
  String get catalogSpecifications => 'Specifications';

  @override
  String get catalogNoProductsInCategory =>
      'There are no products in this category yet.';

  @override
  String get catalogAdjustFilters => 'Try adjusting your filters or search.';

  @override
  String get catalogViewCart => 'View cart';

  @override
  String get catalogYouMayAlsoLike => 'You may also like';

  @override
  String catalogReviews(int count) {
    return '$count reviews';
  }

  @override
  String get catalogBuyNowPayLater => 'Buy now, pay later with zero interest.';

  @override
  String get homeExploreCategories => 'Explore categories';

  @override
  String get homePopularProducts => 'Popular products';

  @override
  String get homeRecentlyOrdered => 'Recently ordered';

  @override
  String get homeShopNow => 'Shop now';

  @override
  String get homeContinueShopping => 'Continue shopping';

  @override
  String get homeEnableLocation => 'Enable location';

  @override
  String get homeSpecialSale => 'Special Sale 🔥';

  @override
  String get homeTapToTrack => 'Tap to track your order';

  @override
  String get authCreateAccount => 'Create account';

  @override
  String get authVerifyContinue => 'Verify & continue';

  @override
  String get authVerifiedNumber => 'Verified number';

  @override
  String get authUseDifferentNumber => 'Use a different number';

  @override
  String get authReferralCode => 'Referral code';

  @override
  String get commonOptional => 'Optional';

  @override
  String get authAlmostThere => 'Almost there!';

  @override
  String get authWantCredit => 'Want shop-now-pay-later?';

  @override
  String get authTermsOfService => 'Terms of Service';

  @override
  String get authGoToHome => 'Go to home';

  @override
  String get billingPurchase => 'Purchase';

  @override
  String get billingPenalty => 'Penalty';

  @override
  String get billingAdjustment => 'Adjustment';

  @override
  String get billingRefund => 'Refund';

  @override
  String get billingCompleted => 'Completed';

  @override
  String get billingReversed => 'Reversed';

  @override
  String get billingOverdue => 'Overdue';

  @override
  String get billingAssigned => 'Assigned';

  @override
  String get billingBankTransfer => 'Bank transfer';

  @override
  String get billingCashCollection => 'Cash collection';

  @override
  String get billingInvoices => 'Invoices';

  @override
  String get billingInvoice => 'Invoice';

  @override
  String get billingStatement => 'Statement';

  @override
  String get billingTransactions => 'Transactions';

  @override
  String get billingMakePayment => 'Make payment';

  @override
  String get billingEnterAmount => 'Enter amount';

  @override
  String get billingAmount => 'Amount';

  @override
  String get billingAmountDue => 'Amount due';

  @override
  String get billingAmountPaid => 'Amount paid';

  @override
  String get billingPayNow => 'Pay now';

  @override
  String get billingDate => 'Date';

  @override
  String get billingStatus => 'Status';

  @override
  String get billingMethod => 'Method';

  @override
  String get billingReference => 'Reference';

  @override
  String get billingNotes => 'Notes (optional)';

  @override
  String get billingDownloadReceipt => 'Download receipt';

  @override
  String get commonDownload => 'Download';

  @override
  String get billingViewOrder => 'View order';

  @override
  String get billingViewStatement => 'View statement';

  @override
  String get billingRequestCollection => 'Request collection';

  @override
  String get billingCollections => 'Collections';

  @override
  String get billingCollected => 'Collected';

  @override
  String get billingAgent => 'Agent';

  @override
  String get billingPaymentSuccessful => 'Payment successful';

  @override
  String get billingTotalOutstanding => 'Total outstanding';

  @override
  String get billingTotalAmountDue => 'Total amount due';

  @override
  String get billingCurrentBill => 'Current bill';

  @override
  String get billingRecentActivity => 'Recent activity';

  @override
  String get billingBreakdown => 'Breakdown';

  @override
  String get billingPrincipal => 'Principal';

  @override
  String get billingInterest => 'Interest';

  @override
  String get billingLateFee => 'Late fee';

  @override
  String get billingInvoiceNumber => 'Invoice number';

  @override
  String get billingInvoiceDate => 'Invoice date';

  @override
  String get billingCreditSummary => 'Credit summary';

  @override
  String get billingBackToDashboard => 'Back to dashboard';

  @override
  String get billingNoInvoices => 'No invoices yet';

  @override
  String get billingNoPayments => 'No payments yet';

  @override
  String get billingNoStatements => 'No statements yet';

  @override
  String get billingNoCollections => 'No collection requests';

  @override
  String get billingNoTransactions => 'No transactions yet';

  @override
  String get billingAllCaughtUp => 'All caught up';

  @override
  String get billingNoPendingDues => 'You have no pending dues right now.';

  @override
  String get billingInvoicesAppearHere =>
      'Invoices for your credit orders will appear here.';

  @override
  String get billingStatementsAppearHere =>
      'Your billing statements will appear here.';

  @override
  String get billingRepaymentsAppearHere =>
      'Your repayments will show up here.';

  @override
  String get billingRepaymentRecorded => 'Your repayment has been recorded.';

  @override
  String get billingSecurePayments => '100% secure payments';

  @override
  String get billingInvoiceNotFound => 'Invoice not found';

  @override
  String get billingStatementNotFound => 'Statement not found';

  @override
  String get profileTitle => 'Profile';

  @override
  String get profileQuickAccess => 'Quick access';

  @override
  String get profileCreditCenter => 'Credit center';

  @override
  String get profileRecentOrders => 'Recent orders';

  @override
  String get profileRecentPayments => 'Recent payments';

  @override
  String get profileNoOrders => 'No orders yet';

  @override
  String get profileNotSignedIn => 'Not signed in';

  @override
  String get profileSignInPrompt => 'Sign in to view and edit your profile.';

  @override
  String get profileSignInCreate => 'Sign in / Create account';

  @override
  String get profilePayDue => 'Pay due';

  @override
  String get profileManageAddresses => 'Manage addresses';

  @override
  String get profileMyReturns => 'My returns';

  @override
  String get profileRewards => 'Rewards';

  @override
  String get profileReferEarn => 'Refer & Earn';

  @override
  String get profileOffersRewards => 'Offers & rewards';

  @override
  String get profileViewOffers => 'View offers';

  @override
  String get profileFaqHelp => 'FAQ & Help';

  @override
  String get profileGender => 'Gender';

  @override
  String get profileDob => 'Date of birth';

  @override
  String get profileChangeNumberNote =>
      'To change your verified number, contact support.';

  @override
  String get profileKycStatus => 'KYC status';

  @override
  String get profileFamilyInfo => 'Family information';

  @override
  String get profileHouseholdMembers => 'Household members';

  @override
  String get profileAddMember => 'Add member';

  @override
  String get profileInviteMember => 'Invite family member';

  @override
  String get profileRemoveMember => 'Remove member';

  @override
  String get profileRelationship => 'Relationship';

  @override
  String get profileActive => 'Active';

  @override
  String get profileCouldNotLoadPayments => 'Could not load payments.';

  @override
  String get creditAmountToPay => 'Amount to pay';

  @override
  String get creditProceedToPayment => 'Proceed to payment';

  @override
  String get creditTxnSuccess => 'Your transaction was completed successfully.';

  @override
  String get creditTransactionId => 'Transaction ID';

  @override
  String get creditNextPaymentDue => 'Next payment due';

  @override
  String get creditPayOutstanding => 'Pay outstanding';

  @override
  String get creditHistory => 'History';

  @override
  String get creditRemaining => 'Remaining credit';

  @override
  String get creditPurchases => 'Purchases';

  @override
  String get creditPaymentsMade => 'Payments made';

  @override
  String get creditAppUnderReview => 'Application under review';

  @override
  String get creditAppNotApproved => 'Application not approved';

  @override
  String get creditScoreIncreased => 'VS Score increased';

  @override
  String get creditGreatBehavior => 'Great financial behavior!';

  @override
  String get creditFinancialStatusUpdated => 'Financial status updated';

  @override
  String get creditTransactionDetails => 'Transaction details';

  @override
  String get checkoutViewOrders => 'View orders';

  @override
  String get checkoutChangeAddress => 'Change address';

  @override
  String get checkoutAmountPayable => 'Amount payable';

  @override
  String get checkoutInclusiveCharges => 'Inclusive of all charges';

  @override
  String get checkoutSelectOption => 'Select option';

  @override
  String get checkoutOnlinePayment => 'Online payment';

  @override
  String get checkoutInstantPayment => 'Instant payment';

  @override
  String get checkoutPayOnDelivery => 'Pay on delivery';

  @override
  String get checkoutPayOnArrival => 'Pay when your order arrives';

  @override
  String get checkoutBuyNowPayLater => 'Buy now, pay later';

  @override
  String get checkoutUpiCardsNetbanking => 'UPI, cards & net banking';

  @override
  String get checkoutCreditDebitCard => 'Credit / Debit card';

  @override
  String get checkoutChooseRepaymentPlan => 'Choose a repayment plan';

  @override
  String get checkoutPayoutDate => 'Payout date';

  @override
  String get checkoutSecuredByRazorpay => 'Payments secured by Razorpay.';

  @override
  String get checkoutOrderConfirmedBody =>
      'Thank you! Your order is confirmed and being prepared.';

  @override
  String get checkoutAgreeTerms =>
      'By placing this order, you agree to our Terms & Conditions and Return Policy.';

  @override
  String get checkoutEnterCoupon => 'Enter a coupon code';

  @override
  String get checkoutCouponValidateFailed => 'Could not validate coupon';

  @override
  String get kycDetailsTitle => 'KYC details';

  @override
  String get kycVerificationTitle => 'KYC verification';

  @override
  String get kycVerificationStatus => 'Verification status';

  @override
  String get kycActionNeeded => 'Action needed';

  @override
  String get kycSubmittedDocs => 'Submitted documents';

  @override
  String get kycNoDocuments => 'No documents on file yet.';

  @override
  String get kycNeedHelp => 'Need help with KYC?';

  @override
  String get kycDataSecured => 'Your data is secured';

  @override
  String get kycChecklist => 'Checklist';

  @override
  String kycReason(String reason) {
    return 'Reason: $reason';
  }

  @override
  String get verifyTitle => 'Verify your identity';

  @override
  String get verifyIdentityDocs => 'Identity documents';

  @override
  String get verifyIdentityVerification => 'Identity verification';

  @override
  String get verifyAadhaar => 'Aadhaar verification';

  @override
  String get verifyPan => 'PAN verification';

  @override
  String get verifyFace => 'Face verification';

  @override
  String get verifySelfie => 'Selfie verification';

  @override
  String get verifyLocation => 'Location verification';

  @override
  String get verifyResidence => 'Residence verification';

  @override
  String get verifyCreditApp => 'Credit application';

  @override
  String get verifyCreditAssessment => 'Credit assessment';

  @override
  String get verifyReviewApp => 'Review your application';

  @override
  String get verifyPersonalDetails => 'Personal details';

  @override
  String get verifyEmploymentDetails => 'Employment details';

  @override
  String get verifyIncomeInfo => 'Income information';

  @override
  String get verifyFinancialInfo => 'Financial information';

  @override
  String get verifyAddressDetails => 'Address details';

  @override
  String get verifyDocuments => 'Documents';

  @override
  String get verifyUploadAadhaar => 'Upload Aadhaar';

  @override
  String get verifyUploadPan => 'Upload PAN photo';

  @override
  String get verifyUploadDocs => 'Upload documents';

  @override
  String get verifyUploadContinue => 'Upload & continue';

  @override
  String get verifyCapture => 'Capture';

  @override
  String get verifyRetake => 'Retake';

  @override
  String get verifyCamera => 'Camera';

  @override
  String get verifyGallery => 'Gallery';

  @override
  String get verifyChooseGallery => 'Choose from gallery';

  @override
  String get verifyStartingCamera => 'Starting camera…';

  @override
  String get verifyCameraNeeded => 'Camera access needed';

  @override
  String get verifyUploaded => 'Uploaded';

  @override
  String get verifyUploadFailed => 'Upload failed';

  @override
  String get verifySaveDraft => 'Save draft';

  @override
  String get verifySubmitApp => 'Submit application';

  @override
  String get verifyReviewBeforeSubmit =>
      'Review each section before submitting for approval.';

  @override
  String get verifyAppSubmitted => 'Application submitted!';

  @override
  String get verifyAppReceived => 'We received your application';

  @override
  String get verifyTeamVerifying => 'Our team is verifying your details';

  @override
  String get verifyPending => 'Verification pending';

  @override
  String get verifyTrackApp => 'Track application';

  @override
  String get verifyReapply => 'Reapply';

  @override
  String get verifyMonthlyIncome => 'Monthly income';

  @override
  String get verifyOccupation => 'Occupation';

  @override
  String get verifyHouseType => 'House type';

  @override
  String get verifyOwnership => 'Ownership';

  @override
  String get verifyFamilyMembers => 'Family members';

  @override
  String get verifyRequestedLimit => 'Requested limit';

  @override
  String get verifyRequestedCreditLimit => 'Requested credit limit';

  @override
  String get verifyApprovedLimit => 'Approved credit limit';

  @override
  String get verifyPotentialLimit => 'Potential credit limit';

  @override
  String get verifyAadhaarNumber => '12-digit Aadhaar number';

  @override
  String get verifyPanNumber => 'PAN number';

  @override
  String get verifyAvailableNow => 'Available now';

  @override
  String get verifyApplicationId => 'Application ID';

  @override
  String get verifySubmittedOn => 'Submitted on';

  @override
  String get verifyExpectedReview => 'Expected review';

  @override
  String get verifyCurrentStatus => 'Current status';

  @override
  String get verifyReason => 'Reason';

  @override
  String get verifyWhyNeed => 'Why we need this';

  @override
  String get verifyPhotoRequirements => 'Photo requirements';

  @override
  String get verifyFaceVisible => 'Ensure your face is clearly visible.';

  @override
  String get verifyPhotoFormat => 'JPG or PNG, up to 5 MB';

  @override
  String get verifySecureEncrypted => '100% secure & encrypted';

  @override
  String verifyStepOf(int step, int total) {
    return 'Step $step of $total';
  }

  @override
  String get supportHowCanWeHelp => 'How can we help you today?';

  @override
  String get supportQuickHelp => 'Quick help topics';

  @override
  String get supportSearchFaqs => 'Search FAQs';

  @override
  String get supportNewConversation => 'New conversation';

  @override
  String get supportOpenConversation => 'Open conversation';

  @override
  String get supportStartConversation => 'Start a conversation';

  @override
  String get supportNoMessages => 'No messages yet';

  @override
  String get supportNoTickets => 'No tickets here';

  @override
  String get supportNoTicketsCategory =>
      'You have no tickets in this category yet.';

  @override
  String get supportTicketDetails => 'Ticket details';

  @override
  String get supportTicketProgress => 'Ticket progress';

  @override
  String get supportIssueCategory => 'Issue category';

  @override
  String get supportIssueDescription => 'Issue description';

  @override
  String get supportPriorityLevel => 'Priority level';

  @override
  String get supportSelectCategory => 'Select an issue category';

  @override
  String get supportDescribeIssue => 'Please describe your issue in detail…';

  @override
  String get supportRelatedOrder => 'Related order (optional)';

  @override
  String get supportAttachments => 'Attachments (optional)';

  @override
  String get supportUploadFile => 'Upload file';

  @override
  String get supportSubmitTicket => 'Submit ticket';

  @override
  String get supportAddReply => 'Add reply';

  @override
  String get supportTypeMessage => 'Type your message…';

  @override
  String get supportSendToStart => 'Send a message to start the conversation.';

  @override
  String get supportCloseTicket => 'Close ticket';

  @override
  String get supportStillNeedHelp => 'Still need help?';

  @override
  String get supportLiveChat => 'Live chat';

  @override
  String get supportCallSupport => 'Call support';

  @override
  String get supportContactInfo => 'Contact information';

  @override
  String get supportRegisteredEmail => 'Registered email';

  @override
  String get supportRegisteredMobile => 'Registered mobile';

  @override
  String get supportResponseTime => 'Estimated response time';

  @override
  String get supportTypicalReply => 'We typically reply within 2 hours';

  @override
  String get supportCategory => 'Category';

  @override
  String get supportCreated => 'Created';

  @override
  String get supportStatusOpen => 'Open';

  @override
  String get supportStatusClosed => 'Closed';

  @override
  String get supportStatusResolved => 'Resolved';

  @override
  String get supportStatusInProgress => 'In progress';

  @override
  String get supportPriorityHigh => 'High priority';

  @override
  String get commonStartShopping => 'Start shopping';

  @override
  String get commonBuyNow => 'Buy now';

  @override
  String get commonShareVia => 'Share via';

  @override
  String get offersAndDeals => 'Offers & deals';

  @override
  String get offersCouponsTitle => 'Coupons & offers';

  @override
  String get offersActiveCoupons => 'Active coupons';

  @override
  String get offersAvailableCoupons => 'Available coupons';

  @override
  String get offersCashback => 'Cashback offers';

  @override
  String get offersCombo => 'Combo offers';

  @override
  String get offersFlashDeals => 'Flash deals';

  @override
  String get offersTopDeals => 'Top deals';

  @override
  String get offersSpecialDeals => 'Special deals';

  @override
  String get offersExpiringSoon => 'Expiring soon';

  @override
  String get offersLimitedTime => 'Limited time';

  @override
  String get offersSellingFast => 'Selling fast';

  @override
  String get offersHowToUse => 'How to use a coupon';

  @override
  String get offersCopy => 'Copy';

  @override
  String get offersNoCoupons => 'No coupons available';

  @override
  String get offersNoCouponsYet => 'No coupons yet';

  @override
  String get offersNoDeals => 'No deals right now';

  @override
  String get offersLoadingDeals => 'Loading deals…';

  @override
  String get offersCouponsAppearHere => 'Coupons you collect will appear here.';

  @override
  String get offersCheckBackSoon => 'Check back soon for fresh savings.';

  @override
  String get offersSaveMore => 'Save more on every order';

  @override
  String get offersCodeCopied => 'Code copied';

  @override
  String get cartBuyOnCredit => 'Buy on Credit';

  @override
  String get cartPayLaterZeroInterest => 'Pay later with zero interest.';

  @override
  String get cartPurchaseMode => 'Purchase mode';

  @override
  String get cartSignInToCheckout => 'Sign in to checkout';

  @override
  String get cartKeepBrowsing => 'Keep browsing';

  @override
  String get cartItemsNeedAttention =>
      'Some items need attention before checkout.';

  @override
  String get wishlistTitle => 'Wishlist';

  @override
  String get wishlistSaved => 'Saved items';

  @override
  String get wishlistEmpty => 'Your wishlist is empty';

  @override
  String get wishlistEmptyBody =>
      'Tap the heart on any product to save it for later.';

  @override
  String get wishlistNoMatch => 'Nothing matches this filter.';

  @override
  String get wishlistTotalValue => 'Total value of wishlist';

  @override
  String get wishlistPriceDropAlerts => 'Price drop alerts';

  @override
  String get wishlistViewProduct => 'View product';

  @override
  String get searchFiltersAndSort => 'Filters & sort';

  @override
  String get searchPopularity => 'Popularity';

  @override
  String get searchPriceLowHigh => 'Price: Low to High';

  @override
  String get searchRating => 'Rating';

  @override
  String get searchTopRated => 'Top rated';

  @override
  String get searchTopRated4Star => 'Top rated (4★ and above)';

  @override
  String get settingsAccountSettings => 'Account settings';

  @override
  String get settingsAppPreferences => 'App preferences';

  @override
  String get settingsSecuritySettings => 'Security settings';

  @override
  String get settingsCreditSettings => 'Credit settings';

  @override
  String get settingsSupportLegal => 'Support & legal';

  @override
  String get settingsEmergencyContacts => 'Emergency contacts';

  @override
  String get settingsNotificationPrefs => 'Notification preferences';

  @override
  String get settingsLocationPermissions => 'Location permissions';

  @override
  String get settingsChangeMpin => 'Change MPIN';

  @override
  String get settingsChangePassword => 'Change password';

  @override
  String get settingsManageDevices => 'Manage devices';

  @override
  String get settingsLoginActivity => 'Login activity';

  @override
  String get settingsBiometricLogin => 'Biometric login';

  @override
  String get settingsBiometricLock => 'Biometric lock';

  @override
  String get settingsAppLock => 'App lock';

  @override
  String get settingsSecurityAlerts => 'Security alerts';

  @override
  String get settingsNotifyNewLogin => 'Notify on new login';

  @override
  String get settingsNotifyProfileChanges => 'Notify on profile changes';

  @override
  String get settingsCreditNotifications => 'Credit notifications';

  @override
  String get settingsPaymentReminders => 'Payment reminders';

  @override
  String get settingsDueDateAlerts => 'Due date alerts';

  @override
  String get settingsStatementNotifications => 'Statement notifications';

  @override
  String get settingsChannelSettings => 'Channel settings';

  @override
  String get settingsHelpCenter => 'Help center';

  @override
  String get settingsDeleteAccountQ => 'Delete account?';

  @override
  String get settingsLogoutQ => 'Log out?';

  @override
  String get settingsAccountDeleted => 'Account deleted. Signing you out…';

  @override
  String get settingsEmergencyContact => 'Emergency contact';

  @override
  String get settingsEmergencyContactSaved => 'Emergency contact saved.';

  @override
  String get settingsContactMobile => 'Contact mobile number';

  @override
  String get settingsCompanyInfo => 'Company information';

  @override
  String get settingsMissionStatement => 'Mission statement';

  @override
  String get settingsWhatWeOffer => 'What we offer';

  @override
  String get settingsGetInTouch => 'Get in touch';

  @override
  String get settingsOfficeAddress => 'Office address';

  @override
  String get settingsLegalCompliance => 'Legal & compliance';

  @override
  String get settingsLicenses => 'Licenses & accreditations';

  @override
  String get settingsWebsite => 'Website';

  @override
  String get reviewsTitle => 'Ratings & reviews';

  @override
  String get reviewsWriteReview => 'Write a review';

  @override
  String get reviewsSubmitReview => 'Submit review';

  @override
  String get reviewsYourRating => 'Your rating';

  @override
  String get reviewsPickRating => 'Please pick a star rating';

  @override
  String get reviewsTitleOptional => 'Title (optional)';

  @override
  String get reviewsSummarise => 'Summarise your experience';

  @override
  String get reviewsYourReview => 'Your review (optional)';

  @override
  String get reviewsLikeDislike => 'What did you like or dislike?';

  @override
  String get reviewsThanks => 'Thanks for your review!';

  @override
  String get reviewsSubmitFailed =>
      'Could not submit review. Please try again.';

  @override
  String get referralInviteFriends => 'Invite friends';

  @override
  String get referralInviteFriendsNow => 'Invite friends now';

  @override
  String get referralHowItWorks => 'How it works';

  @override
  String get referralHaveCode => 'Have a referral code?';

  @override
  String get referralEnterCode => 'Enter a referral code';

  @override
  String get referralCodeApplied => 'Referral code applied';

  @override
  String get referralCodeCopied => 'Code copied';

  @override
  String get referralYouEarn => 'You earn';

  @override
  String get referralFirstOrder => 'First order';

  @override
  String get referralFriendRegisters => 'Friend registers';

  @override
  String get referralInviteCopied =>
      'Invite message copied — paste it to your friends';

  @override
  String get notifGroupOrders => 'Order notifications';

  @override
  String get notifGroupPayments => 'Payment notifications';

  @override
  String get notifGroupCredit => 'Credit notifications';

  @override
  String get notifGroupPromotional => 'Promotional notifications';

  @override
  String get notifOrderConfirmed => 'Order confirmed';

  @override
  String get notifOrderPacked => 'Order packed';

  @override
  String get notifOrderOutForDelivery => 'Order out for delivery';

  @override
  String get notifOrderDelivered => 'Order delivered';

  @override
  String get notifPaymentSuccess => 'Payment success';

  @override
  String get notifPaymentFailure => 'Payment failure';

  @override
  String get notifCollectionReminders => 'Collection reminders';

  @override
  String get notifCreditApproval => 'Credit approval';

  @override
  String get notifCreditLimitUpdates => 'Credit limit updates';

  @override
  String get notifOutstandingDueAlerts => 'Outstanding due alerts';

  @override
  String get notifVsScoreUpdates => 'VS Score updates';

  @override
  String get notifOffers => 'Offers';

  @override
  String get notifCoupons => 'Coupons';

  @override
  String get notifCashback => 'Cashback';

  @override
  String get notifReferralRewards => 'Referral rewards';

  @override
  String get notifPush => 'Push notifications';

  @override
  String get notifSms => 'SMS notifications';

  @override
  String get notifWhatsapp => 'WhatsApp notifications';

  @override
  String get notifEmail => 'Email notifications';

  @override
  String get notifLoadError => 'Couldn\'t load your notification settings.';

  @override
  String get returnsTitle => 'Returns & Refunds';

  @override
  String get returnStatusRequested => 'Requested';

  @override
  String get returnStatusApproved => 'Approved';

  @override
  String get returnStatusRejected => 'Rejected';

  @override
  String get returnStatusPicked => 'Picked Up';

  @override
  String get returnStatusRefunded => 'Refunded';

  @override
  String get returnsEmptyTitle => 'No returns yet';

  @override
  String get returnsEmptyBody =>
      'Returns and refunds you request will appear here.';

  @override
  String returnsOrderNumber(String code) {
    return 'Order $code';
  }

  @override
  String get returnsReasonLabel => 'Reason';

  @override
  String get returnsRefundLabel => 'Refund';

  @override
  String get returnRequestTitle => 'Return / Refund';

  @override
  String get returnRequestOrderLabel => 'Order';

  @override
  String get returnRequestReasonLabel => 'Reason for Return';

  @override
  String get returnRequestSelectReason => 'Select a reason';

  @override
  String get returnRequestDescriptionLabel => 'Description (Optional)';

  @override
  String get returnRequestDescriptionHint => 'Tell us more about the issue...';

  @override
  String get returnRequestSubmit => 'Submit Request';

  @override
  String get returnRequestError =>
      'Could not request a return. Please try again.';

  @override
  String get returnRequestPhotosLabel => 'Photos of the item';

  @override
  String get returnRequestPhotosHint =>
      'Add clear photos showing the item and the issue. Our pickup partner will check these at your door.';

  @override
  String get returnRequestAddPhoto => 'Add photo';

  @override
  String get returnRequestPhotoRequired =>
      'Add at least one photo of the item.';

  @override
  String returnRequestPhotoLimit(int count) {
    return 'You can add up to $count photos.';
  }

  @override
  String get returnRequestRemovePhoto => 'Remove photo';

  @override
  String get returnReasonDamaged => 'Damaged item';

  @override
  String get returnReasonWrong => 'Wrong item';

  @override
  String get returnReasonQuality => 'Quality issue';

  @override
  String get returnReasonChangedMind => 'Changed my mind';

  @override
  String get returnReasonOther => 'Other';

  @override
  String get onboardingSlide1Caption => 'Fresh Groceries, Delivered Fast!';

  @override
  String get onboardingSlide1Title =>
      'Fresh Groceries Delivered To Your Doorstep';

  @override
  String get onboardingSlide1Body =>
      'Order vegetables, fruits, dairy products, household essentials, and daily groceries with fast delivery.';

  @override
  String get onboardingSlide2Caption => 'Shop Now, Pay Later';

  @override
  String get onboardingSlide2Title => 'Shop With VS Credit, Pay On Your Terms';

  @override
  String get onboardingSlide2Body =>
      'Buy what you need today and settle later with flexible weekly or monthly credit — no hidden charges.';

  @override
  String get onboardingSlide3Caption => 'Grow Your VS Score';

  @override
  String get onboardingSlide3Title => 'Build Your Credit Score As You Shop';

  @override
  String get onboardingSlide3Body =>
      'Every on-time payment strengthens your VS Score and unlocks higher credit limits and better offers.';

  @override
  String get onboardingGetStarted => 'Get Started';

  @override
  String get systemUpdateTitle => 'Update Required';

  @override
  String get systemUpdateBody =>
      'A newer version of VS Mart is available with important improvements. Please update from the Play Store to continue.';

  @override
  String get systemUpdateNow => 'Update Now';

  @override
  String get systemUpdatedCheckAgain => 'I\'ve updated — Check again';

  @override
  String get systemPlayStoreError =>
      'Could not open the Play Store. Please search for \"VS Mart\" to update.';

  @override
  String get systemMaintenanceTitle => 'Under Maintenance';

  @override
  String get systemMaintenanceBody =>
      'We\'re sprucing things up and will be back shortly. Thanks for your patience.';

  @override
  String get systemTryAgain => 'Try Again';

  @override
  String get systemNoInternetTitle => 'No Internet Connection';

  @override
  String get systemNoInternetBody => 'Check your connection and try again.';

  @override
  String get collectionConfirmTitle => 'Confirm Payment';

  @override
  String get collectionConfirmLoadError => 'Couldn\'t load the confirmation.';

  @override
  String get collectionConfirmNothingTitle => 'Nothing to confirm';

  @override
  String get collectionConfirmNothingBody =>
      'You have no pending cash collection right now.';

  @override
  String collectionConfirmCollecting(String name) {
    return '$name is collecting';
  }

  @override
  String get collectionConfirmShareCode => 'SHARE THIS CODE';

  @override
  String collectionConfirmSafetyWarning(String amount) {
    return 'Only share this code if you are paying $amount in cash. Never share it otherwise.';
  }

  @override
  String get collectionConfirmDoneTitle => 'Payment confirmed';

  @override
  String collectionConfirmDoneBody(String name, String amount) {
    return '$name has received $amount in cash.';
  }

  @override
  String get locationPickerTitle => 'Set your location';

  @override
  String get locationConfirm => 'Confirm location';

  @override
  String get locationDragHint => 'Drag the map or tap to place the pin';

  @override
  String get locationCouldNotGet => 'Couldn\'t get your location.';

  @override
  String get locationPermissionNeeded => 'Location permission needed.';

  @override
  String get locationSearchSubtitle =>
      'Find your area, then drop the pin on your exact spot.';

  @override
  String get locationSearchHint => 'Search area, street or landmark';

  @override
  String get locationPlaceLoadError =>
      'Couldn\'t load that place. Try another.';

  @override
  String get locationSearchUnavailable =>
      'Search isn\'t available right now. Use your current location, or check your connection and retry.';

  @override
  String get locationNoMatches => 'No matches. Try a different search.';

  @override
  String get paymentReminderTitle => 'Payment Reminders';

  @override
  String get paymentReminderLoadError =>
      'Couldn\'t load your reminder preferences.';

  @override
  String get paymentReminderSaved => 'Reminder preferences saved.';

  @override
  String get paymentReminderSaveError => 'Could not save preferences.';

  @override
  String get paymentReminderHeadline => 'Stay on track';

  @override
  String get paymentReminderSubtitle =>
      'Configure your alerts to avoid late fees and maintain a healthy credit score with VS Mart.';

  @override
  String get paymentReminderEnableTitle => 'Enable Reminders';

  @override
  String get paymentReminderEnableSubtitle =>
      'Get notified before your due date';

  @override
  String get paymentReminderWhenTitle => 'When should we remind you?';

  @override
  String get paymentReminderThreeDays => '3 Days Before';

  @override
  String get paymentReminderThreeDaysSub => 'Best for planning ahead';

  @override
  String get paymentReminderOneDay => '1 Day Before';

  @override
  String get paymentReminderOneDaySub => 'Quick reminder';

  @override
  String get paymentReminderOnDueDate => 'On Due Date';

  @override
  String get paymentReminderOnDueDateSub => 'Morning of payment';

  @override
  String get paymentReminderWeekBefore => 'A Week Before';

  @override
  String get paymentReminderWeekBeforeSub => 'Maximum lead time';

  @override
  String get paymentReminderHowTitle => 'How should we reach you?';

  @override
  String get paymentReminderWhatsApp => 'WhatsApp';

  @override
  String get paymentReminderWhatsAppSub => 'Instant message delivery';

  @override
  String get paymentReminderPush => 'Push Notification';

  @override
  String get paymentReminderPushSub => 'Direct to your VS Mart app';

  @override
  String get paymentReminderSms => 'SMS Text';

  @override
  String get paymentReminderSmsSub => 'Standard text message';

  @override
  String get paymentReminderPreferredTime => 'Preferred Time';

  @override
  String get paymentReminderTimeOfDay => 'Time of day';

  @override
  String get paymentReminderInfoBanner =>
      'Setting reminders helps you avoid late fees and positively impacts your credit health by ensuring timely payments.';

  @override
  String get paymentReminderSave => 'Save Preferences';

  @override
  String get supportFaqsHeadline => 'Frequently Asked Questions';

  @override
  String get supportFaqsLoadError => 'Couldn\'t load FAQs.';

  @override
  String get supportNoFaqsMatch => 'No FAQs match your search.';

  @override
  String get supportTeamHereToAssist =>
      'Our support team is here to assist you.';

  @override
  String get supportContactSupport => 'Contact Support';

  @override
  String get supportAttachLimit => 'You can attach up to 3 files.';

  @override
  String get supportTicketSubmitted => 'Ticket submitted';

  @override
  String get supportTapToUploadPhotos => 'Tap to upload photos';

  @override
  String get supportMaxFilesSize => 'Max 3 files, 5MB each';

  @override
  String get supportRespondsWithin24h =>
      'Our team typically responds within 24 hours.';

  @override
  String supportTicketCode(String id) {
    return 'Ticket VS-TKT-$id';
  }

  @override
  String supportTicketOpened(String id) {
    return 'Ticket VS-TKT-$id opened';
  }

  @override
  String get supportSearchPrompt =>
      'Search for help, orders, payments, credit issues…';

  @override
  String get supportTicketNotFound => 'Ticket not found.';

  @override
  String get supportCloseTicketQ => 'Close this ticket?';

  @override
  String get supportCloseTicketBody =>
      'This tells our team the issue is resolved and stops further work on it. You can always raise a new ticket later.';

  @override
  String get supportTicketClosed => 'Ticket closed.';

  @override
  String settingsCouldNotOpen(String target) {
    return 'Could not open $target.';
  }

  @override
  String get settingsOpenTargetDialer => 'the dialer';

  @override
  String get settingsOpenTargetEmail => 'your email app';

  @override
  String get settingsOpenTargetLink => 'the link';

  @override
  String get settingsCompanyDescription =>
      'VS Mart is a pioneering hybrid ecosystem bridging the gap between daily grocery commerce and flexible financial credit, ensuring families have seamless access to essentials when they need them most.';

  @override
  String get settingsMissionText =>
      '\"To empower communities by providing fresh, affordable groceries coupled with trustworthy, flexible credit solutions, creating a stress-free shopping experience.\"';

  @override
  String get settingsOfferGroceryTitle => 'Grocery Shopping';

  @override
  String get settingsOfferGrocerySubtitle => 'Fresh daily essentials';

  @override
  String get settingsOfferCreditSubtitle => 'Flexible payment options';

  @override
  String get settingsOfferDeliveryTitle => 'Delivery Services';

  @override
  String get settingsOfferDeliverySubtitle => 'Fast & reliable delivery';

  @override
  String get settingsOfferCollectionsTitle => 'Digital Collections';

  @override
  String get settingsOfferCollectionsSubtitle => 'Seamless repayment';

  @override
  String settingsAllRightsReserved(String app) {
    return '© 2026 $app. All rights reserved.';
  }

  @override
  String get settingsBiometricLockSubtitle =>
      'Require fingerprint / Face ID to open VS Mart';

  @override
  String get settingsNotifyNewLoginSubtitle =>
      'Get notified when your account signs in';

  @override
  String get settingsNotifyProfileChangesSubtitle =>
      'Alert me when account details change';

  @override
  String get settingsOtpSecurityNote =>
      'Your VS Mart account is secured with one-time password (OTP) login on every sign-in.';

  @override
  String get settingsNoAccountContact =>
      'We could not find your account contact. Please sign in again.';

  @override
  String get settingsDeletionRequested =>
      'Deletion requested — we\'ll process it and remove your account.';

  @override
  String get billingCreditTab => 'Credit';

  @override
  String get billingCreditPendingBody =>
      'We\'re verifying your details. Your VS Credit line will unlock here once approved — usually within a few hours.';

  @override
  String get billingViewStatus => 'View Status';

  @override
  String get billingCreditRejectedBody =>
      'Your last credit application wasn\'t approved. You can review your details and apply again.';

  @override
  String get billingUnlockCredit => 'Unlock VS Credit';

  @override
  String get billingCreditApplyBody =>
      'Shop now and pay later with a VS Credit line. Complete a quick KYC verification to apply — it only takes a few minutes.';

  @override
  String get billingApplyForCredit => 'Apply for Credit';

  @override
  String get billingCreditEncryptedNote =>
      'Your information is encrypted and used only for credit verification.';

  @override
  String get billingBenefitShopPayLater => 'Shop Now, Pay Later';

  @override
  String get billingBenefitFlexiblePlans => 'Flexible Weekly / Monthly Plans';

  @override
  String get billingBenefitMemberOffers => 'Exclusive Member Offers';

  @override
  String get billingBenefitBuildScore => 'Build Your VS Score';

  @override
  String get billingWhyVsCredit => 'Why VS Credit?';

  @override
  String billingPercentUsed(int percent) {
    return '$percent% used';
  }

  @override
  String billingUsedAmount(String amount) {
    return 'Used: $amount';
  }

  @override
  String billingTotalLimitAmount(String amount) {
    return 'Total Limit: $amount';
  }

  @override
  String get billingCollectionRequestRaised =>
      'Collection request raised. An agent will be assigned to visit you.';

  @override
  String get billingCollectionAddress => 'Collection Address';

  @override
  String get billingRegisteredAddress => 'Registered address';

  @override
  String get billingAgentVisitAddress =>
      'The agent will visit your saved delivery address';

  @override
  String get billingCollectionNotesHint =>
      'Any instructions for the collection agent (optional)';

  @override
  String get billingCollectionAgentInfo =>
      'A VS Mart collection agent will be assigned and visit your location to collect the payment securely. You will be notified once an agent is confirmed.';

  @override
  String get billingAmountToCollect => 'Amount to Collect';

  @override
  String get billingEnterValidAmount => 'Enter a valid amount';

  @override
  String get billingRequest => 'Request';

  @override
  String get billingCollectionsAppearHere =>
      'Cash collection pickups you request will appear here.';

  @override
  String billingRequestedOn(String date) {
    return 'Requested $date';
  }

  @override
  String get billingAddress => 'Address';

  @override
  String billingOrderDate(String order, String date) {
    return 'Order $order • $date';
  }

  @override
  String get billingInvoiceLoadError => 'Could not load the invoice';

  @override
  String get billingOutstandingDue => 'Outstanding Due';

  @override
  String get billingDuesLoadError => 'Couldn\'t load your dues.';

  @override
  String billingDueOnDate(String date) {
    return 'Due: $date';
  }

  @override
  String billingOverdueByDays(int days) {
    return 'Overdue by $days Days';
  }

  @override
  String billingDueInDays(int days) {
    return 'Due in $days Days';
  }

  @override
  String get billingTotalOutstandingAmount => 'Total Outstanding Amount';

  @override
  String get billingPayBeforeDueNote =>
      'Pay before the due date to maintain a healthy VS Score and avoid late fees.';

  @override
  String get billingPayingTotalAmount => 'Paying Total Amount';

  @override
  String get billingReceiptDownloaded => 'Receipt downloaded';

  @override
  String get billingCollectionRequested =>
      'Collection requested. An agent will be assigned.';

  @override
  String get billingCollectionRequestError =>
      'Could not raise the request. Try again.';

  @override
  String get billingPaymentFailed => 'Payment failed. Please try again.';

  @override
  String get billingProceedToPay => 'Proceed to Pay';

  @override
  String get billingOutstandingAmount => 'Outstanding amount';

  @override
  String get billingDebitCreditCard => 'Debit / Credit card';

  @override
  String get billingNeftImpsTransfer => 'NEFT / IMPS transfer';

  @override
  String get billingRequestAgentPickup => 'Request an agent pickup';

  @override
  String get billingCreditUpdated => 'Credit updated';

  @override
  String get billingStatementDownloaded => 'Statement downloaded';

  @override
  String get billingNoTransactionsInCycle => 'No transactions in this cycle.';

  @override
  String billingPayAmount(String amount) {
    return 'Pay $amount';
  }

  @override
  String get billingStatusDue => 'Due';

  @override
  String get billingGenerated => 'Generated';

  @override
  String billingBalanceAmount(String amount) {
    return 'Bal $amount';
  }

  @override
  String billingPaymentDue(String date) {
    return 'Payment due $date';
  }

  @override
  String billingAmountDueMin(String amount, String min) {
    return '$amount due • min $min';
  }

  @override
  String billingAmountDueShort(String amount) {
    return '$amount due';
  }

  @override
  String get billingPay => 'Pay';

  @override
  String get kycDobHelpText => 'Date of birth (as per PAN)';

  @override
  String get kycApplyVsCredit => 'Apply for VS Credit';

  @override
  String get kycStep1VerifyDetails => 'Step 1 of 2 · Verify your details';

  @override
  String get kycDetailsIntro =>
      'Enter your details as on your PAN. We\'ll fetch your CIBIL score on your registered number to verify your identity.';

  @override
  String get kycNameAsPerPan => 'Name as per PAN';

  @override
  String get kycFullNameHint => 'e.g. Srinivasu Magapu';

  @override
  String get kycSelectDob => 'Select your date of birth';

  @override
  String get kycCheckCibil => 'Check CIBIL';

  @override
  String get kycIdentityVerified => 'Identity verified';

  @override
  String kycCibilScore(String score) {
    return 'CIBIL $score';
  }

  @override
  String get kycStep2Documents => 'Step 2 of 2 · Upload documents';

  @override
  String get kycDocsIntro =>
      'Clear photos of both sides of your Aadhaar and PAN cards. An agent will verify them.';

  @override
  String get kycAadhaarFront => 'Aadhaar — front';

  @override
  String get kycAadhaarBack => 'Aadhaar — back';

  @override
  String get kycPanFront => 'PAN — front';

  @override
  String get kycPanBack => 'PAN — back';

  @override
  String get kycSubmitForVerification => 'Submit for verification';

  @override
  String get kycApplicationSubmitted => 'Application submitted';

  @override
  String get kycApplicationSubmittedBody =>
      'An agent will be assigned to verify your documents. Your VS Credit limit unlocks once they approve.';

  @override
  String get kycYourCibilScore => 'Your CIBIL Score';

  @override
  String get kycTapToChange => 'Tap to change';

  @override
  String get kycTapToUpload => 'Tap to upload';

  @override
  String get kycConsentText =>
      'I authorise VS Mart to fetch my credit score from the bureau to verify my identity and assess my credit eligibility.';

  @override
  String get kycLiveSelfie => 'Live Selfie';

  @override
  String get kycMobileVerified => 'Mobile Verified';

  @override
  String get kycAddressAdded => 'Address Added';

  @override
  String get kycStatusLoadError => 'Couldn\'t load your verification status.';

  @override
  String get kycResubmitDocuments => 'Re-submit Documents';

  @override
  String get kycCompleteToUnlock =>
      'Complete verification to unlock VS Credit benefits.';

  @override
  String get kycInstantVerification => 'Instant verification';

  @override
  String get kycInstantVerifyBody =>
      'Verify with your PAN & credit score in a minute';

  @override
  String kycStepsCompleted(int completed, int total) {
    return '$completed of $total Steps Completed';
  }

  @override
  String get kycBenefitOnApproval => 'On approval';

  @override
  String get kycBenefitFlexiblePlans => 'Flexible Plans';

  @override
  String get kycBenefitWeeklyMonthly => 'Weekly / Monthly';

  @override
  String get kycBenefitExclusiveOffers => 'Exclusive Offers';

  @override
  String get kycBenefitMemberOnly => 'Member Only';

  @override
  String get kycBenefitBuildCredit => 'Build Credit';

  @override
  String get kycUnlockBenefits => 'Unlock VS Credit Benefits';

  @override
  String get kycSecurityNote =>
      'Your information is encrypted and securely stored following bank-grade security standards.';

  @override
  String get kycSecurityBannerBody =>
      'KYC verification is required to unlock your full credit limit and ensure compliance with RBI regulations. We use bank-grade encryption.';

  @override
  String get kycCaptionVerified =>
      'All required documents have been successfully verified.';

  @override
  String get kycCaptionPending =>
      'Your documents are under review. This usually takes 1–2 days.';

  @override
  String get kycCaptionRejected =>
      'Some documents could not be verified. Please re-submit.';

  @override
  String get kycCaptionNotStarted =>
      'Complete your KYC to unlock your full credit limit.';

  @override
  String kycPercentComplete(int percent) {
    return '$percent% Complete';
  }

  @override
  String get kycStartCardBody =>
      'Submit your Aadhaar, PAN and a selfie to verify your identity.';

  @override
  String get kycSubmitted => 'Submitted';

  @override
  String get commonOr => 'OR';

  @override
  String discountPercentOff(int percent) {
    return '$percent% OFF';
  }

  @override
  String get serviceCheckingArea => 'Checking your area…';

  @override
  String get serviceConfirmingDelivery =>
      'Confirming we deliver where you are.';

  @override
  String get serviceSetLocationTitle => 'Set your location to continue';

  @override
  String get serviceNotInAreaTitle => 'VS Mart isn\'t in your area yet';

  @override
  String get serviceCouldntConfirmBody =>
      'We couldn\'t confirm your location. Set it so we can check if VS Mart delivers near you.';

  @override
  String get serviceExpandingBody =>
      'We\'re expanding fast. Change your location to shop from a serviceable area near you.';

  @override
  String get serviceNotifyWhenHere => 'Notify me when you\'re here';

  @override
  String get serviceLocationOffNote =>
      'Location is turned off on your phone. Turn it on, then try again.';

  @override
  String get serviceOpenLocationSettings => 'Open location settings';

  @override
  String get serviceLocationBlockedNote =>
      'Location permission is blocked for VS Mart. Enable it in Settings, then try again.';

  @override
  String get serviceOpenAppSettings => 'Open app settings';

  @override
  String get serviceNoGpsFixNote =>
      'Couldn\'t get a GPS fix. Move near a window or step outside and try again, or search for your area instead.';

  @override
  String get serviceDontDeliverThereNote =>
      'We don\'t deliver there yet. Try a different location.';

  @override
  String get serviceChangeLocationBody =>
      'Use your current location, or search your area and drop the pin.';

  @override
  String get serviceUseMyCurrentLocation => 'Use my current location';

  @override
  String get serviceSearchAreaDropPin => 'Search area & drop pin';

  @override
  String get serviceOpenSettings => 'Open settings';

  @override
  String get serviceEnterValidPhone => 'Enter a valid phone number';

  @override
  String get serviceNotifyBody =>
      'Leave your number and we\'ll message you the moment VS Mart starts delivering in your area.';

  @override
  String get serviceNameOptional => 'Name (optional)';

  @override
  String get servicePhoneHintExample => 'e.g. +9198XXXXXXXX';

  @override
  String get serviceWellNotifyYou => 'We\'ll notify you';

  @override
  String get serviceNotifySuccessBody =>
      'Thanks! We\'ve registered your interest and will message you as soon as we start delivering near you.';

  @override
  String get wishlistBrowseProducts => 'Browse Products';

  @override
  String get wishlistPriceDrop => 'Price Drop';

  @override
  String wishlistRemoved(String name) {
    return '$name removed from wishlist';
  }

  @override
  String get searchUnderPrice => 'Under ₹99';

  @override
  String searchResultsFound(int count) {
    return '$count Results found';
  }

  @override
  String searchNoResultsFor(String query) {
    return 'We couldn\'t find anything for \"$query\".';
  }

  @override
  String get searchSortPrefix => 'Sort: ';

  @override
  String searchFiltersApplied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Filters Applied',
      one: '1 Filter Applied',
    );
    return '$_temp0';
  }

  @override
  String get searchForPrefix => 'Search for ';

  @override
  String reviewsTooLong(int max) {
    return 'Your review is too long (max $max characters).';
  }

  @override
  String reviewsRatingValue(int rating) {
    return '$rating out of 5 stars';
  }

  @override
  String reviewsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count reviews',
      one: '1 review',
    );
    return '$_temp0';
  }

  @override
  String get reviewsNoneYet => 'No reviews yet — be the first';

  @override
  String reviewsRateStars(int star) {
    String _temp0 = intl.Intl.pluralLogic(
      star,
      locale: localeName,
      other: 'Rate $star stars',
      one: 'Rate 1 star',
    );
    return '$_temp0';
  }

  @override
  String get referralCodeHint => 'e.g. VS00042';

  @override
  String get referralTermsApply => 'Terms & Conditions Apply';

  @override
  String referralEarnPerReferral(String amount) {
    return 'Earn $amount Per Successful Referral';
  }

  @override
  String get referralNoneYet => 'No referrals yet — invite to start earning';

  @override
  String referralSuccessfulCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count successful referrals',
      one: '1 successful referral',
    );
    return '$_temp0';
  }

  @override
  String get referralYourCode => 'Your Referral Code';

  @override
  String get referralStepShareBody => 'Share your unique link or code.';

  @override
  String get referralStepRegisterBody => 'They sign up using your code.';

  @override
  String get referralStepOrderBody => 'They place their first valid order.';

  @override
  String referralStepEarnBody(String amount) {
    return 'Get $amount added to your wallet.';
  }

  @override
  String get offersCouldntLoadDeals => 'Couldn\'t load deals.';

  @override
  String get offersCouldntLoadCoupons => 'Couldn\'t load coupons.';

  @override
  String get offersUpTo60Off => 'Up to 60% OFF';

  @override
  String get offersOnGroceries => 'On groceries & daily essentials';

  @override
  String get offersTodaysDeals => 'Today\'s Deals';

  @override
  String get offersMegaSavings => 'Today\'s Mega Savings';

  @override
  String get offersUpTo60OffProduce =>
      'Up to 60% off on fresh produce & essentials';

  @override
  String get offersFilterFlashSale => 'Flash Sale';

  @override
  String get offersFilterTopDiscounts => 'Top Discounts';

  @override
  String get offersFilterBuy1Get1 => 'Buy 1 Get 1';

  @override
  String get offersOnlyFiveLeft => 'Only 5 left!';

  @override
  String get offersClaimedPercent => '80% Claimed';

  @override
  String offersCodeLabel(String code) {
    return 'Code: $code';
  }

  @override
  String get loyaltyRedeemPoints => 'Redeem Points';

  @override
  String get loyaltyRewardPoints => 'Reward Points';

  @override
  String get loyaltyPointsAvailable => 'points available';

  @override
  String loyaltyLifetimeEarned(String points) {
    return 'Lifetime earned: $points pts';
  }

  @override
  String get loyaltyNoActivity => 'No points activity yet';

  @override
  String get loyaltyNoActivityBody =>
      'Earn and redeem points to see your history here.';

  @override
  String get loyaltyPointsEarned => 'Points earned';

  @override
  String get loyaltyPointsRedeemed => 'Points redeemed';

  @override
  String get loyaltyPointsExpired => 'Points expired';

  @override
  String get loyaltyPointsAdjustment => 'Points adjustment';

  @override
  String get loyaltyEnterValidPoints => 'Enter a valid number of points';

  @override
  String loyaltyOnlyHavePoints(String points) {
    return 'You only have $points points';
  }

  @override
  String loyaltyPointsAvailableSentence(String points) {
    return 'You have $points points available.';
  }

  @override
  String get loyaltyPointsToRedeem => 'Points to redeem';

  @override
  String get loyaltyPointsHint => 'e.g. 100';

  @override
  String get loyaltyRedeem => 'Redeem';

  @override
  String get notificationsAllCaughtUp => 'You\'re all caught up.';

  @override
  String get notificationsYesterday => 'Yesterday';

  @override
  String homeOrderNumber(String id) {
    return 'Order #$id';
  }

  @override
  String get homeCouldntLoad => 'Couldn\'t load';

  @override
  String get checkoutCouldNotPlaceOrder =>
      'Could not place order. Please review your cart.';

  @override
  String checkoutQty(int count) {
    return 'Qty $count';
  }

  @override
  String checkoutCouponAppliedOff(String code, String amount) {
    return '“$code” applied — $amount off';
  }

  @override
  String checkoutDueDate(String date) {
    return 'Due $date';
  }

  @override
  String get paymentCouldNotComplete =>
      'Could not complete payment. Check your cart and address.';

  @override
  String get paymentNotCompleted =>
      'Payment not completed. Your order is saved — you can retry from My Orders.';

  @override
  String get cartItemsUnavailableTitle => 'Some items are unavailable';

  @override
  String get cartItemsUnavailableBody =>
      'These went out of stock at your store. Remove them to continue.';

  @override
  String get cartRemoveAndContinue => 'Remove & continue';

  @override
  String get cartReviewCart => 'Review cart';

  @override
  String get cartSignInBody =>
      'Create an account or sign in to place your order and pay. Your cart will be waiting for you.';

  @override
  String get cartTotalEstimateError =>
      'Couldn\'t fetch the latest total — showing an estimate. Tap to retry.';

  @override
  String ordersOrderNumber(Object id) {
    return 'Order #$id';
  }

  @override
  String get ordersCancelConfirmTitle => 'Cancel order?';

  @override
  String get ordersCancelConfirmBody =>
      'Cancel this order? This can\'t be undone.';

  @override
  String get ordersKeepOrder => 'Keep order';

  @override
  String get ordersCancelled => 'Order cancelled';

  @override
  String get ordersTimeline => 'Order Timeline';

  @override
  String ordersItemQuantity(Object name, int quantity) {
    return '$name  ×$quantity';
  }

  @override
  String get ordersPayment => 'Payment';

  @override
  String get ordersCreditUsed => 'Credit Used';

  @override
  String get ordersOrderPlaced => 'Order Placed';

  @override
  String get ordersOrderStatus => 'Order status';

  @override
  String ordersArrivingIn(String eta) {
    return 'Arriving in $eta';
  }

  @override
  String get ordersOnTheWayHeadline => 'Your order is on the way';

  @override
  String get ordersWeWillUpdate => 'We\'ll update you as it moves';

  @override
  String get ordersContactWhenAssigned =>
      'Contact appears once a rider is assigned.';

  @override
  String get ordersDialerError => 'Could not open the dialer.';

  @override
  String get ordersDeliveryPartner => 'Delivery Partner';

  @override
  String get ordersRiderOnTheWay => 'On the way';

  @override
  String get ordersPreparingYourOrder => 'We\'re preparing your order';

  @override
  String get ordersDeliveryFailedHint =>
      'We couldn\'t complete this delivery. Our team will be in touch about the next attempt.';

  @override
  String get ordersOrderClosedHint =>
      'This order is closed. You can review what was ordered below.';

  @override
  String get ordersMapUnavailable =>
      'Live map appears once your delivery address has a pinned location.';

  @override
  String ordersMoreItems(int count) {
    return '+$count more';
  }

  @override
  String ordersItemsAddedToCart(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items added to cart',
      one: '1 item added to cart',
    );
    return '$_temp0';
  }

  @override
  String get ordersItemsUnavailable => 'Those items are unavailable right now';

  @override
  String get ordersOrderedAt => 'Ordered at';

  @override
  String get ordersDeliveredAt => 'Delivered at';

  @override
  String get ordersFeedbackThanks => 'Thanks for the feedback!';

  @override
  String get ordersYouRated => 'You rated this order';

  @override
  String get ordersHowWasDelivery => 'How was your delivery?';

  @override
  String get ordersFeedbackHelps => 'Your feedback helps us improve.';

  @override
  String ordersAgentDelivered(Object name) {
    return '$name delivered this order.';
  }

  @override
  String get ordersFeedbackHint => 'Anything to add? (optional)';

  @override
  String get ordersSendFeedback => 'Send feedback';

  @override
  String ordersStarCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stars',
      one: '1 star',
    );
    return '$_temp0';
  }

  @override
  String get profileLogoutConfirmBody =>
      'You will need to sign in again to access your account.';

  @override
  String get profileBrowsingAsGuest => 'You\'re browsing as a guest';

  @override
  String get profileGuestSignInBody =>
      'Sign in to place orders, track deliveries and unlock VS Credit.';

  @override
  String get profileGuest => 'Guest';

  @override
  String profileCreditAmount(Object amount) {
    return 'Credit $amount';
  }

  @override
  String profileScoreValue(Object score) {
    return 'Score $score';
  }

  @override
  String profileUsedAmount(Object amount) {
    return 'Used: $amount';
  }

  @override
  String profileLimitAmount(Object amount) {
    return 'Limit: $amount';
  }

  @override
  String get profileAddresses => 'Addresses';

  @override
  String get profilePayments => 'Payments';

  @override
  String get profileSupport => 'Support';

  @override
  String get profileMonthlyStatement => 'Monthly Statement';

  @override
  String get profileOutstandingDue => 'Outstanding Due';

  @override
  String get profileCreditUsage => 'Credit Usage';

  @override
  String get profileVsScoreDetails => 'VS Score Details';

  @override
  String get profileNoSavedAddress => 'No saved address yet.';

  @override
  String get profilePaymentUpi => 'UPI Payment';

  @override
  String get profilePaymentCard => 'Card Payment';

  @override
  String get profilePaymentBankTransfer => 'Bank Transfer';

  @override
  String get profilePaymentCashCollection => 'Cash Collection';

  @override
  String get profileViewHistory => 'View History';

  @override
  String get profileKycAadhaar => 'Aadhaar';

  @override
  String get profileKycSelfie => 'Selfie';

  @override
  String get profileKycHouse => 'House Verification';

  @override
  String profileActiveCoupons(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Active Coupons',
      one: '1 Active Coupon',
    );
    return '$_temp0';
  }

  @override
  String get profileLanguageEnglish => 'Language (English)';

  @override
  String get profileAboutVsMart => 'About VS Mart';

  @override
  String get profileCareers => 'Careers';

  @override
  String get profileYou => 'You';

  @override
  String get profilePrimaryHolder => 'Primary Account Holder';

  @override
  String get profileFamilyMember => 'Family Member';

  @override
  String get profileInvitationPending => 'Invitation pending';

  @override
  String get profileHouseholdMember => 'Household member';

  @override
  String profileMemberRemoved(Object name) {
    return '$name removed.';
  }

  @override
  String get profileRelationshipHint => 'Relationship (e.g. Spouse)';

  @override
  String get profileInvite => 'Invite';

  @override
  String profileInviteSent(Object phone) {
    return 'Invite sent to $phone.';
  }

  @override
  String get profileHouseholdLoadError => 'Couldn\'t load your household.';

  @override
  String get profileFamilySubtitle =>
      'Manage shared credit limits and shopping profiles for your family.';

  @override
  String get profileSharedLimitUsage => 'Shared Limit Usage';

  @override
  String get profileAddHouseholdMember => 'Add a Household Member';

  @override
  String get profileAddMemberBody =>
      'Invite family to share your VS Mart credit limit and shopping lists.';

  @override
  String get profileUpdated => 'Profile updated';

  @override
  String get profilePhotoUpdated => 'Profile photo updated.';

  @override
  String get profileNameHint => 'e.g. Jane Doe';

  @override
  String get profileEmailHint => 'you@example.com';

  @override
  String get catalogProductNotFound => 'Product not found.';

  @override
  String get catalogRemovedFromWishlist => 'Removed from wishlist';

  @override
  String get catalogAddedToWishlist => 'Added to wishlist';

  @override
  String get catalogShareSheetError => 'Couldn\'t open the share sheet.';

  @override
  String get catalogDefaultDescription =>
      'Farm-fresh and hand-selected for quality, delivered at peak freshness.';

  @override
  String get catalogEligibleForCredit => 'Eligible for VS Credit';

  @override
  String catalogBrowseAllIn(Object name) {
    return 'Browse all in $name';
  }

  @override
  String get catalogViewProducts => 'View products';

  @override
  String get catalogDecreaseQuantity => 'Decrease quantity';

  @override
  String get catalogIncreaseQuantity => 'Increase quantity';

  @override
  String get catalogHandpickedDaily => 'Handpicked daily from trusted farms';

  @override
  String get catalogNothingHere => 'Nothing here';

  @override
  String get catalogFreshPicksIn => 'Fresh picks in';

  @override
  String get catalogHandpickedQuality =>
      'Handpicked, quality-checked, delivered fast';

  @override
  String get catalogShareLinkCopied => 'Share link copied';

  @override
  String catalogAddedToCart(Object name) {
    return '$name added to cart';
  }

  @override
  String catalogPercentOff(Object percent) {
    return '$percent% OFF';
  }

  @override
  String catalogPriceOnCredit(Object price) {
    return '$price on VS Credit';
  }

  @override
  String catalogPriceRange(Object min, Object max) {
    return '₹$min – ₹$max';
  }

  @override
  String catalogDiscountOff(Object percent) {
    return '$percent%+ off';
  }

  @override
  String get verificationAadhaarInvalid =>
      'Enter a valid 12-digit Aadhaar number';

  @override
  String get verificationOtpSentAadhaar =>
      'OTP sent to your Aadhaar-linked mobile';

  @override
  String get verificationEnterOtpReceived => 'Enter the OTP you received';

  @override
  String get verificationAadhaarVerified => 'Aadhaar verified';

  @override
  String get verificationCouldNotCaptureImage => 'Could not capture image';

  @override
  String get verificationUploadAadhaarBoth =>
      'Please upload Aadhaar front and back';

  @override
  String get verificationRequiredForCredit => 'Required to activate VS Credit.';

  @override
  String get verificationOtpOptionalNote =>
      'Optional — only needed if you can\'t receive the OTP.';

  @override
  String get verificationAadhaarFront => 'Aadhaar Front';

  @override
  String get verificationAadhaarBack => 'Aadhaar Back';

  @override
  String get verificationCantReceiveOtp =>
      'Can\'t receive OTP? Continue with documents';

  @override
  String get verificationWhyAadhaarTitle => 'We use Aadhaar verification to:';

  @override
  String get verificationReviewingDetails =>
      'Our team is reviewing your details. Your credit limit will reflect in your profile once approved.';

  @override
  String get verificationCreditReflectionNote =>
      'Credit reflection may take up to 2–4 hours after approval.';

  @override
  String get verificationCompleteSelections => 'Please complete all selections';

  @override
  String get verificationHelpDetermineEligibility =>
      'Help us determine your credit eligibility.';

  @override
  String get verificationHousehold => 'Household';

  @override
  String get verificationDraftSaved => 'Draft saved';

  @override
  String get verificationInitialAssessment =>
      'Based on initial profile assessment.';

  @override
  String get verificationUploadAllDocs =>
      'Please upload all required documents';

  @override
  String get verificationWhyDocumentsTitle => 'We use your documents to:';

  @override
  String get verificationPanConsentRequired =>
      'Please allow us to verify your PAN to continue';

  @override
  String get verificationPanVerified => 'PAN verified';

  @override
  String get verificationPanComplianceNote =>
      'Your PAN is required for financial compliance.';

  @override
  String get verificationRiskEvaluation => 'Risk Evaluation';

  @override
  String get verificationPanConsentText =>
      'I consent to VS Mart verifying my PAN with the Income Tax department for KYC.';

  @override
  String get verificationVerifyPan => 'Verify PAN';

  @override
  String get verificationSubmitYourDetails => 'Please submit your details.';

  @override
  String get verificationResidencePhotoAttached => 'Residence photo attached.';

  @override
  String get verificationCameraGalleryError =>
      'Could not access the camera/gallery.';

  @override
  String get verificationAddResidencePhoto =>
      'Please add a photo of your residence.';

  @override
  String get verificationCaptureLocationFirst =>
      'Capture your location before submitting.';

  @override
  String get verificationResidenceSubmitted =>
      'Residence verification submitted.';

  @override
  String get verificationResidenceIntro =>
      'Please upload a clear photo of your residence to verify your address for faster processing and secure deliveries.';

  @override
  String get verificationSampleApprovedImage => 'Sample Approved Image';

  @override
  String get verificationIdeal => 'Ideal';

  @override
  String get verificationLatitude => 'Latitude';

  @override
  String get verificationLongitude => 'Longitude';

  @override
  String get verificationSubmissionFailed =>
      'Submission failed. Please try again.';

  @override
  String get verificationAddress => 'Address';

  @override
  String get verificationSelfie => 'Selfie';

  @override
  String get verificationCreditInformation => 'Credit Information';

  @override
  String get verificationHouse => 'House';

  @override
  String get verificationCompleteAllSections =>
      'Complete all sections to submit your application.';

  @override
  String get verificationApplicationSubmitted => 'Application Submitted';

  @override
  String get verificationCreditDecision => 'Credit eligibility decision';

  @override
  String verificationApplicationRef(Object id) {
    return 'Application $id';
  }

  @override
  String get verificationNotifyDecision =>
      'We\'ll notify you the moment a decision is made. You can keep browsing in the meantime.';

  @override
  String verificationUploading(Object title) {
    return 'Uploading $title…';
  }

  @override
  String get verificationLimitLabel => 'limit';

  @override
  String get verificationCaptureFailed => 'Capture failed';

  @override
  String get verificationSelfieCaptured => 'Selfie captured';
}
