import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_te.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('hi'),
    Locale('te'),
  ];

  /// Short brand tagline
  ///
  /// In en, this message translates to:
  /// **'Groceries in minutes'**
  String get appTagline;

  /// No description provided for @commonOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get commonApply;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get commonContinue;

  /// No description provided for @commonNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get commonNext;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get commonYes;

  /// No description provided for @commonNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get commonNo;

  /// No description provided for @commonSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get commonSearch;

  /// No description provided for @commonSeeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get commonSeeAll;

  /// No description provided for @commonLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get commonLoading;

  /// No description provided for @commonSomethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get commonSomethingWentWrong;

  /// No description provided for @commonNoInternet.
  ///
  /// In en, this message translates to:
  /// **'No internet connection'**
  String get commonNoInternet;

  /// No description provided for @commonTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Please try again'**
  String get commonTryAgain;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navCategories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get navCategories;

  /// No description provided for @navCart.
  ///
  /// In en, this message translates to:
  /// **'Cart'**
  String get navCart;

  /// No description provided for @navOrders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get navOrders;

  /// No description provided for @navAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get navAccount;

  /// No description provided for @navCredit.
  ///
  /// In en, this message translates to:
  /// **'VS Credit'**
  String get navCredit;

  /// No description provided for @homeSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search for groceries, brands and more'**
  String get homeSearchHint;

  /// No description provided for @homeDeliverTo.
  ///
  /// In en, this message translates to:
  /// **'Deliver to'**
  String get homeDeliverTo;

  /// No description provided for @homeOffersForYou.
  ///
  /// In en, this message translates to:
  /// **'Offers for you'**
  String get homeOffersForYou;

  /// No description provided for @homeRecommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended for you'**
  String get homeRecommended;

  /// No description provided for @homePopular.
  ///
  /// In en, this message translates to:
  /// **'Popular near you'**
  String get homePopular;

  /// No description provided for @homeShopByCategory.
  ///
  /// In en, this message translates to:
  /// **'Shop by category'**
  String get homeShopByCategory;

  /// ETA chip on the home serviceability banner
  ///
  /// In en, this message translates to:
  /// **'Delivery in {minutes} min'**
  String serviceDeliveringIn(int minutes);

  /// Shows the serving store name
  ///
  /// In en, this message translates to:
  /// **'from {store}'**
  String serviceFrom(String store);

  /// No description provided for @serviceNotAvailableTitle.
  ///
  /// In en, this message translates to:
  /// **'We are not available in your area yet'**
  String get serviceNotAvailableTitle;

  /// No description provided for @serviceNotAvailableBody.
  ///
  /// In en, this message translates to:
  /// **'VS Mart doesn\'t deliver to this location right now. Tell us where you are and we\'ll notify you when we launch.'**
  String get serviceNotAvailableBody;

  /// No description provided for @serviceChangeLocation.
  ///
  /// In en, this message translates to:
  /// **'Change location'**
  String get serviceChangeLocation;

  /// No description provided for @serviceNotifyMe.
  ///
  /// In en, this message translates to:
  /// **'Notify me'**
  String get serviceNotifyMe;

  /// No description provided for @serviceStoreClosed.
  ///
  /// In en, this message translates to:
  /// **'Store currently closed'**
  String get serviceStoreClosed;

  /// Shown when the serving store is outside business hours
  ///
  /// In en, this message translates to:
  /// **'Store is closed. Orders resume at {time}.'**
  String serviceStoreClosedResumesAt(String time);

  /// No description provided for @serviceSlotsFull.
  ///
  /// In en, this message translates to:
  /// **'Today\'s delivery slots are full'**
  String get serviceSlotsFull;

  /// No description provided for @productAddToCart.
  ///
  /// In en, this message translates to:
  /// **'Add to cart'**
  String get productAddToCart;

  /// No description provided for @productAdded.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get productAdded;

  /// No description provided for @productOutOfStock.
  ///
  /// In en, this message translates to:
  /// **'Out of stock'**
  String get productOutOfStock;

  /// No description provided for @productInCart.
  ///
  /// In en, this message translates to:
  /// **'In cart'**
  String get productInCart;

  /// Discount savings badge
  ///
  /// In en, this message translates to:
  /// **'Save {amount}'**
  String productSave(String amount);

  /// No description provided for @cartTitle.
  ///
  /// In en, this message translates to:
  /// **'My cart'**
  String get cartTitle;

  /// No description provided for @cartEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Your cart is empty'**
  String get cartEmptyTitle;

  /// No description provided for @cartEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Add items to get started'**
  String get cartEmptyBody;

  /// No description provided for @cartSubtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get cartSubtotal;

  /// No description provided for @cartDeliveryFee.
  ///
  /// In en, this message translates to:
  /// **'Delivery fee'**
  String get cartDeliveryFee;

  /// No description provided for @cartGst.
  ///
  /// In en, this message translates to:
  /// **'GST'**
  String get cartGst;

  /// No description provided for @cartTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get cartTotal;

  /// No description provided for @cartFree.
  ///
  /// In en, this message translates to:
  /// **'FREE'**
  String get cartFree;

  /// Item count in the cart
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No items} =1{1 item} other{{count} items}}'**
  String cartItemsCount(int count);

  /// No description provided for @cartProceedToCheckout.
  ///
  /// In en, this message translates to:
  /// **'Proceed to checkout'**
  String get cartProceedToCheckout;

  /// No description provided for @checkoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Checkout'**
  String get checkoutTitle;

  /// No description provided for @checkoutDeliveryAddress.
  ///
  /// In en, this message translates to:
  /// **'Delivery address'**
  String get checkoutDeliveryAddress;

  /// No description provided for @checkoutPaymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Payment method'**
  String get checkoutPaymentMethod;

  /// No description provided for @checkoutPlaceOrder.
  ///
  /// In en, this message translates to:
  /// **'Place order'**
  String get checkoutPlaceOrder;

  /// No description provided for @checkoutPayNow.
  ///
  /// In en, this message translates to:
  /// **'Pay now'**
  String get checkoutPayNow;

  /// No description provided for @checkoutCod.
  ///
  /// In en, this message translates to:
  /// **'Cash on delivery'**
  String get checkoutCod;

  /// No description provided for @checkoutUpi.
  ///
  /// In en, this message translates to:
  /// **'UPI'**
  String get checkoutUpi;

  /// No description provided for @checkoutCard.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get checkoutCard;

  /// No description provided for @checkoutVsCredit.
  ///
  /// In en, this message translates to:
  /// **'VS Credit'**
  String get checkoutVsCredit;

  /// No description provided for @checkoutOrderPlacedTitle.
  ///
  /// In en, this message translates to:
  /// **'Order placed!'**
  String get checkoutOrderPlacedTitle;

  /// Order confirmation
  ///
  /// In en, this message translates to:
  /// **'Your order {code} has been placed.'**
  String checkoutOrderPlacedBody(String code);

  /// No description provided for @creditTitle.
  ///
  /// In en, this message translates to:
  /// **'VS Credit'**
  String get creditTitle;

  /// No description provided for @creditLimit.
  ///
  /// In en, this message translates to:
  /// **'Credit limit'**
  String get creditLimit;

  /// No description provided for @creditAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available credit'**
  String get creditAvailable;

  /// No description provided for @creditOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Outstanding'**
  String get creditOutstanding;

  /// Outstanding-due banner. {amount} is a pre-formatted currency string like ₹25,000.
  ///
  /// In en, this message translates to:
  /// **'You have {amount} outstanding'**
  String creditOutstandingAmount(String amount);

  /// Repayment due date
  ///
  /// In en, this message translates to:
  /// **'Due on {date}'**
  String creditDueOn(String date);

  /// No description provided for @creditRepay.
  ///
  /// In en, this message translates to:
  /// **'Repay'**
  String get creditRepay;

  /// No description provided for @creditRepayNow.
  ///
  /// In en, this message translates to:
  /// **'Repay now'**
  String get creditRepayNow;

  /// No description provided for @creditPayBill.
  ///
  /// In en, this message translates to:
  /// **'Pay bill'**
  String get creditPayBill;

  /// No description provided for @creditFrozen.
  ///
  /// In en, this message translates to:
  /// **'Your credit is temporarily frozen'**
  String get creditFrozen;

  /// No description provided for @creditCompleteKyc.
  ///
  /// In en, this message translates to:
  /// **'Complete KYC to use VS Credit'**
  String get creditCompleteKyc;

  /// No description provided for @kycTitle.
  ///
  /// In en, this message translates to:
  /// **'Verification'**
  String get kycTitle;

  /// No description provided for @kycCompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Complete your KYC'**
  String get kycCompleteTitle;

  /// No description provided for @kycPending.
  ///
  /// In en, this message translates to:
  /// **'Verification in progress'**
  String get kycPending;

  /// No description provided for @kycVerified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get kycVerified;

  /// No description provided for @kycRejected.
  ///
  /// In en, this message translates to:
  /// **'Verification rejected'**
  String get kycRejected;

  /// No description provided for @kycUploadDocument.
  ///
  /// In en, this message translates to:
  /// **'Upload document'**
  String get kycUploadDocument;

  /// No description provided for @kycVerifyIdentity.
  ///
  /// In en, this message translates to:
  /// **'Verify identity'**
  String get kycVerifyIdentity;

  /// No description provided for @ordersTitle.
  ///
  /// In en, this message translates to:
  /// **'My orders'**
  String get ordersTitle;

  /// No description provided for @ordersEmpty.
  ///
  /// In en, this message translates to:
  /// **'You have no orders yet'**
  String get ordersEmpty;

  /// No description provided for @ordersTrack.
  ///
  /// In en, this message translates to:
  /// **'Track order'**
  String get ordersTrack;

  /// No description provided for @reorderSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Add these to your cart?'**
  String get reorderSheetTitle;

  /// Primary button on the reorder review sheet.
  ///
  /// In en, this message translates to:
  /// **'Add {count} to cart'**
  String reorderAddAll(int count);

  /// No description provided for @reorderUnavailableHeading.
  ///
  /// In en, this message translates to:
  /// **'Not available right now'**
  String get reorderUnavailableHeading;

  /// No description provided for @reorderDiscontinued.
  ///
  /// In en, this message translates to:
  /// **'No longer sold'**
  String get reorderDiscontinued;

  /// No description provided for @reorderOutOfStock.
  ///
  /// In en, this message translates to:
  /// **'Out of stock'**
  String get reorderOutOfStock;

  /// No description provided for @reorderNothingAvailable.
  ///
  /// In en, this message translates to:
  /// **'None of these items are available right now.'**
  String get reorderNothingAvailable;

  /// No description provided for @reorderPricesMayHaveChanged.
  ///
  /// In en, this message translates to:
  /// **'Prices shown are today\'s.'**
  String get reorderPricesMayHaveChanged;

  /// No description provided for @ordersAmountPaid.
  ///
  /// In en, this message translates to:
  /// **'Amount paid'**
  String get ordersAmountPaid;

  /// No description provided for @ordersAmountRefunded.
  ///
  /// In en, this message translates to:
  /// **'Refunded'**
  String get ordersAmountRefunded;

  /// No description provided for @ordersRefundPending.
  ///
  /// In en, this message translates to:
  /// **'Refund not yet issued'**
  String get ordersRefundPending;

  /// No description provided for @deliveryOtpTitle.
  ///
  /// In en, this message translates to:
  /// **'Delivery OTP'**
  String get deliveryOtpTitle;

  /// No description provided for @deliveryOtpShare.
  ///
  /// In en, this message translates to:
  /// **'Share this code with your rider at the door'**
  String get deliveryOtpShare;

  /// No description provided for @profileOrderArriving.
  ///
  /// In en, this message translates to:
  /// **'Your order is arriving'**
  String get profileOrderArriving;

  /// No description provided for @profileShowOtp.
  ///
  /// In en, this message translates to:
  /// **'Tap to track and view your delivery OTP'**
  String get profileShowOtp;

  /// No description provided for @ordersReorder.
  ///
  /// In en, this message translates to:
  /// **'Reorder'**
  String get ordersReorder;

  /// No description provided for @orderStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get orderStatusPending;

  /// No description provided for @orderStatusConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get orderStatusConfirmed;

  /// No description provided for @orderStatusPacked.
  ///
  /// In en, this message translates to:
  /// **'Packed'**
  String get orderStatusPacked;

  /// No description provided for @orderStatusOutForDelivery.
  ///
  /// In en, this message translates to:
  /// **'Out for delivery'**
  String get orderStatusOutForDelivery;

  /// No description provided for @orderStatusDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get orderStatusDelivered;

  /// No description provided for @orderStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get orderStatusCancelled;

  /// No description provided for @accountTitle.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountTitle;

  /// No description provided for @accountSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get accountSettings;

  /// No description provided for @accountLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get accountLanguage;

  /// No description provided for @accountLogout.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get accountLogout;

  /// No description provided for @languageTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageTitle;

  /// No description provided for @languageSelect.
  ///
  /// In en, this message translates to:
  /// **'Select language'**
  String get languageSelect;

  /// No description provided for @languageCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current language'**
  String get languageCurrent;

  /// No description provided for @languageApply.
  ///
  /// In en, this message translates to:
  /// **'Apply language'**
  String get languageApply;

  /// No description provided for @languageUpdated.
  ///
  /// In en, this message translates to:
  /// **'Language updated'**
  String get languageUpdated;

  /// No description provided for @languagePreview.
  ///
  /// In en, this message translates to:
  /// **'Language preview'**
  String get languagePreview;

  /// No description provided for @codeOutsideServiceAreaTitle.
  ///
  /// In en, this message translates to:
  /// **'Service unavailable'**
  String get codeOutsideServiceAreaTitle;

  /// No description provided for @codeOutsideServiceAreaBody.
  ///
  /// In en, this message translates to:
  /// **'VS Mart currently doesn\'t deliver to your location.'**
  String get codeOutsideServiceAreaBody;

  /// No description provided for @codeStoreClosedTitle.
  ///
  /// In en, this message translates to:
  /// **'Store closed'**
  String get codeStoreClosedTitle;

  /// No description provided for @codeStoreClosedBody.
  ///
  /// In en, this message translates to:
  /// **'The store for your area isn\'t accepting orders right now.'**
  String get codeStoreClosedBody;

  /// No description provided for @codeCapacityReachedTitle.
  ///
  /// In en, this message translates to:
  /// **'Delivery slots full'**
  String get codeCapacityReachedTitle;

  /// No description provided for @codeCapacityReachedBody.
  ///
  /// In en, this message translates to:
  /// **'Today\'s delivery capacity for your area is full. Please try again tomorrow.'**
  String get codeCapacityReachedBody;

  /// No description provided for @codeStoreChangedTitle.
  ///
  /// In en, this message translates to:
  /// **'Delivery area changed'**
  String get codeStoreChangedTitle;

  /// No description provided for @codeStoreChangedBody.
  ///
  /// In en, this message translates to:
  /// **'Your delivery address moved to a different store\'s area, so your cart was refreshed.'**
  String get codeStoreChangedBody;

  /// No description provided for @codeProductUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Not available at your store'**
  String get codeProductUnavailableTitle;

  /// No description provided for @codeProductUnavailableBody.
  ///
  /// In en, this message translates to:
  /// **'Some items in your cart aren\'t carried by the store serving your area.'**
  String get codeProductUnavailableBody;

  /// No description provided for @codeOutOfStockTitle.
  ///
  /// In en, this message translates to:
  /// **'Item unavailable'**
  String get codeOutOfStockTitle;

  /// No description provided for @codeOutOfStockBody.
  ///
  /// In en, this message translates to:
  /// **'One or more items in your cart are out of stock.'**
  String get codeOutOfStockBody;

  /// No description provided for @codeKycRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Verification required'**
  String get codeKycRequiredTitle;

  /// No description provided for @codeKycRequiredBody.
  ///
  /// In en, this message translates to:
  /// **'Complete KYC before paying with VS Credit.'**
  String get codeKycRequiredBody;

  /// No description provided for @codeCreditDisabledTitle.
  ///
  /// In en, this message translates to:
  /// **'Credit unavailable'**
  String get codeCreditDisabledTitle;

  /// No description provided for @codeCreditDisabledBody.
  ///
  /// In en, this message translates to:
  /// **'VS Credit isn\'t available for this order.'**
  String get codeCreditDisabledBody;

  /// No description provided for @codeLimitExceededTitle.
  ///
  /// In en, this message translates to:
  /// **'Limit exceeded'**
  String get codeLimitExceededTitle;

  /// No description provided for @codeLimitExceededBody.
  ///
  /// In en, this message translates to:
  /// **'This order exceeds your available credit.'**
  String get codeLimitExceededBody;

  /// No description provided for @codeOverduePaymentTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment overdue'**
  String get codeOverduePaymentTitle;

  /// No description provided for @codeOverduePaymentBody.
  ///
  /// In en, this message translates to:
  /// **'Clear your overdue dues before placing a new credit order.'**
  String get codeOverduePaymentBody;

  /// No description provided for @codeSessionExpiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Session expired'**
  String get codeSessionExpiredTitle;

  /// No description provided for @codeSessionExpiredBody.
  ///
  /// In en, this message translates to:
  /// **'Please sign in again to continue.'**
  String get codeSessionExpiredBody;

  /// No description provided for @commonEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get commonRemove;

  /// No description provided for @commonUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get commonUpdate;

  /// No description provided for @commonConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get commonConfirm;

  /// No description provided for @commonSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get commonSubmit;

  /// No description provided for @commonShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get commonShare;

  /// No description provided for @commonViewDetails.
  ///
  /// In en, this message translates to:
  /// **'View details'**
  String get commonViewDetails;

  /// No description provided for @commonViewAll.
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get commonViewAll;

  /// No description provided for @commonChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get commonChange;

  /// No description provided for @commonAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get commonAdd;

  /// No description provided for @commonProceed.
  ///
  /// In en, this message translates to:
  /// **'Proceed'**
  String get commonProceed;

  /// No description provided for @commonSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get commonSkip;

  /// No description provided for @commonRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get commonRefresh;

  /// No description provided for @commonClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get commonClearAll;

  /// No description provided for @commonComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get commonComingSoon;

  /// No description provided for @commonNoData.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get commonNoData;

  /// No description provided for @authWelcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome to VS Mart'**
  String get authWelcome;

  /// No description provided for @authEnterPhone.
  ///
  /// In en, this message translates to:
  /// **'Enter your mobile number'**
  String get authEnterPhone;

  /// No description provided for @authPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'Mobile number'**
  String get authPhoneHint;

  /// No description provided for @authSendOtp.
  ///
  /// In en, this message translates to:
  /// **'Send OTP'**
  String get authSendOtp;

  /// No description provided for @authEnterOtp.
  ///
  /// In en, this message translates to:
  /// **'Enter OTP'**
  String get authEnterOtp;

  /// No description provided for @authOtpSentTo.
  ///
  /// In en, this message translates to:
  /// **'OTP sent to {phone}'**
  String authOtpSentTo(String phone);

  /// No description provided for @authVerify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get authVerify;

  /// No description provided for @authResendOtp.
  ///
  /// In en, this message translates to:
  /// **'Resend OTP'**
  String get authResendOtp;

  /// No description provided for @authResendIn.
  ///
  /// In en, this message translates to:
  /// **'Resend in {seconds}s'**
  String authResendIn(int seconds);

  /// No description provided for @authTermsAgree.
  ///
  /// In en, this message translates to:
  /// **'By continuing you agree to our Terms & Privacy Policy'**
  String get authTermsAgree;

  /// No description provided for @authLoginToContinue.
  ///
  /// In en, this message translates to:
  /// **'Log in to continue'**
  String get authLoginToContinue;

  /// No description provided for @accountEditProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get accountEditProfile;

  /// No description provided for @accountMyAddresses.
  ///
  /// In en, this message translates to:
  /// **'My addresses'**
  String get accountMyAddresses;

  /// No description provided for @accountPaymentMethods.
  ///
  /// In en, this message translates to:
  /// **'Payment methods'**
  String get accountPaymentMethods;

  /// No description provided for @accountHelpSupport.
  ///
  /// In en, this message translates to:
  /// **'Help & support'**
  String get accountHelpSupport;

  /// No description provided for @accountAboutUs.
  ///
  /// In en, this message translates to:
  /// **'About us'**
  String get accountAboutUs;

  /// No description provided for @accountTerms.
  ///
  /// In en, this message translates to:
  /// **'Terms & conditions'**
  String get accountTerms;

  /// No description provided for @accountPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get accountPrivacy;

  /// No description provided for @accountRateUs.
  ///
  /// In en, this message translates to:
  /// **'Rate us'**
  String get accountRateUs;

  /// No description provided for @accountShareApp.
  ///
  /// In en, this message translates to:
  /// **'Share app'**
  String get accountShareApp;

  /// No description provided for @accountDeleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get accountDeleteAccount;

  /// No description provided for @accountVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String accountVersion(String version);

  /// No description provided for @accountPersonalDetails.
  ///
  /// In en, this message translates to:
  /// **'Personal details'**
  String get accountPersonalDetails;

  /// No description provided for @accountName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get accountName;

  /// No description provided for @accountEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get accountEmail;

  /// No description provided for @accountPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get accountPhone;

  /// No description provided for @accountSaveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get accountSaveChanges;

  /// No description provided for @orderDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Order details'**
  String get orderDetailsTitle;

  /// No description provided for @orderId.
  ///
  /// In en, this message translates to:
  /// **'Order ID'**
  String get orderId;

  /// No description provided for @orderPlacedOn.
  ///
  /// In en, this message translates to:
  /// **'Placed on {date}'**
  String orderPlacedOn(String date);

  /// No description provided for @orderItems.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get orderItems;

  /// No description provided for @orderBillDetails.
  ///
  /// In en, this message translates to:
  /// **'Bill details'**
  String get orderBillDetails;

  /// No description provided for @orderDownloadInvoice.
  ///
  /// In en, this message translates to:
  /// **'Download invoice'**
  String get orderDownloadInvoice;

  /// No description provided for @orderNeedHelp.
  ///
  /// In en, this message translates to:
  /// **'Need help?'**
  String get orderNeedHelp;

  /// No description provided for @orderCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel order'**
  String get orderCancel;

  /// No description provided for @orderRate.
  ///
  /// In en, this message translates to:
  /// **'Rate order'**
  String get orderRate;

  /// No description provided for @orderSummary.
  ///
  /// In en, this message translates to:
  /// **'Order summary'**
  String get orderSummary;

  /// No description provided for @orderDeliveryDetails.
  ///
  /// In en, this message translates to:
  /// **'Delivery details'**
  String get orderDeliveryDetails;

  /// No description provided for @orderItemTotal.
  ///
  /// In en, this message translates to:
  /// **'Item total'**
  String get orderItemTotal;

  /// No description provided for @orderGrandTotal.
  ///
  /// In en, this message translates to:
  /// **'Grand total'**
  String get orderGrandTotal;

  /// No description provided for @orderSaved.
  ///
  /// In en, this message translates to:
  /// **'You saved {amount}'**
  String orderSaved(String amount);

  /// No description provided for @creditStatements.
  ///
  /// In en, this message translates to:
  /// **'Statements'**
  String get creditStatements;

  /// No description provided for @creditPaymentHistory.
  ///
  /// In en, this message translates to:
  /// **'Payment history'**
  String get creditPaymentHistory;

  /// No description provided for @creditRepayment.
  ///
  /// In en, this message translates to:
  /// **'Repayment'**
  String get creditRepayment;

  /// No description provided for @creditDueDate.
  ///
  /// In en, this message translates to:
  /// **'Due date'**
  String get creditDueDate;

  /// No description provided for @creditMinimumDue.
  ///
  /// In en, this message translates to:
  /// **'Minimum due'**
  String get creditMinimumDue;

  /// No description provided for @creditTotalDue.
  ///
  /// In en, this message translates to:
  /// **'Total due'**
  String get creditTotalDue;

  /// No description provided for @creditTransactionHistory.
  ///
  /// In en, this message translates to:
  /// **'Transaction history'**
  String get creditTransactionHistory;

  /// No description provided for @creditScore.
  ///
  /// In en, this message translates to:
  /// **'VS Score'**
  String get creditScore;

  /// No description provided for @creditUsed.
  ///
  /// In en, this message translates to:
  /// **'Used'**
  String get creditUsed;

  /// No description provided for @creditRepaymentPlan.
  ///
  /// In en, this message translates to:
  /// **'Repayment plan'**
  String get creditRepaymentPlan;

  /// No description provided for @creditWeekend.
  ///
  /// In en, this message translates to:
  /// **'Weekend'**
  String get creditWeekend;

  /// No description provided for @creditMonthEnd.
  ///
  /// In en, this message translates to:
  /// **'Month end'**
  String get creditMonthEnd;

  /// No description provided for @creditPayFull.
  ///
  /// In en, this message translates to:
  /// **'Pay full amount'**
  String get creditPayFull;

  /// No description provided for @creditNoDues.
  ///
  /// In en, this message translates to:
  /// **'You have no dues'**
  String get creditNoDues;

  /// No description provided for @checkoutSelectAddress.
  ///
  /// In en, this message translates to:
  /// **'Select delivery address'**
  String get checkoutSelectAddress;

  /// No description provided for @checkoutAddNewAddress.
  ///
  /// In en, this message translates to:
  /// **'Add new address'**
  String get checkoutAddNewAddress;

  /// No description provided for @checkoutApplyCoupon.
  ///
  /// In en, this message translates to:
  /// **'Apply coupon'**
  String get checkoutApplyCoupon;

  /// No description provided for @checkoutCouponApplied.
  ///
  /// In en, this message translates to:
  /// **'Coupon applied'**
  String get checkoutCouponApplied;

  /// No description provided for @checkoutBillSummary.
  ///
  /// In en, this message translates to:
  /// **'Bill summary'**
  String get checkoutBillSummary;

  /// No description provided for @checkoutItemTotal.
  ///
  /// In en, this message translates to:
  /// **'Item total'**
  String get checkoutItemTotal;

  /// No description provided for @checkoutSavings.
  ///
  /// In en, this message translates to:
  /// **'Savings'**
  String get checkoutSavings;

  /// No description provided for @checkoutGrandTotal.
  ///
  /// In en, this message translates to:
  /// **'Grand total'**
  String get checkoutGrandTotal;

  /// No description provided for @checkoutPaymentOptions.
  ///
  /// In en, this message translates to:
  /// **'Payment options'**
  String get checkoutPaymentOptions;

  /// No description provided for @checkoutDeliverySlot.
  ///
  /// In en, this message translates to:
  /// **'Delivery slot'**
  String get checkoutDeliverySlot;

  /// No description provided for @addressAdd.
  ///
  /// In en, this message translates to:
  /// **'Add address'**
  String get addressAdd;

  /// No description provided for @addressEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit address'**
  String get addressEdit;

  /// No description provided for @addressFullName.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get addressFullName;

  /// No description provided for @addressPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get addressPhone;

  /// No description provided for @addressPincode.
  ///
  /// In en, this message translates to:
  /// **'Pincode'**
  String get addressPincode;

  /// No description provided for @addressHouseNo.
  ///
  /// In en, this message translates to:
  /// **'House / flat no.'**
  String get addressHouseNo;

  /// No description provided for @addressArea.
  ///
  /// In en, this message translates to:
  /// **'Area / locality'**
  String get addressArea;

  /// No description provided for @addressLandmark.
  ///
  /// In en, this message translates to:
  /// **'Landmark'**
  String get addressLandmark;

  /// No description provided for @addressCity.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get addressCity;

  /// No description provided for @addressState.
  ///
  /// In en, this message translates to:
  /// **'State'**
  String get addressState;

  /// No description provided for @addressSave.
  ///
  /// In en, this message translates to:
  /// **'Save address'**
  String get addressSave;

  /// No description provided for @addressSetDefault.
  ///
  /// In en, this message translates to:
  /// **'Set as default'**
  String get addressSetDefault;

  /// No description provided for @addressType.
  ///
  /// In en, this message translates to:
  /// **'Address type'**
  String get addressType;

  /// No description provided for @addressHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get addressHome;

  /// No description provided for @addressWork.
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get addressWork;

  /// No description provided for @addressOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get addressOther;

  /// No description provided for @addressUseCurrentLocation.
  ///
  /// In en, this message translates to:
  /// **'Use current location'**
  String get addressUseCurrentLocation;

  /// No description provided for @addressNone.
  ///
  /// In en, this message translates to:
  /// **'No saved addresses'**
  String get addressNone;

  /// No description provided for @notificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

  /// No description provided for @notificationsMarkAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all as read'**
  String get notificationsMarkAllRead;

  /// No description provided for @notificationsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet'**
  String get notificationsEmpty;

  /// No description provided for @notificationsToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get notificationsToday;

  /// No description provided for @notificationsEarlier.
  ///
  /// In en, this message translates to:
  /// **'Earlier'**
  String get notificationsEarlier;

  /// No description provided for @supportTitle.
  ///
  /// In en, this message translates to:
  /// **'Help & support'**
  String get supportTitle;

  /// No description provided for @supportContactUs.
  ///
  /// In en, this message translates to:
  /// **'Contact us'**
  String get supportContactUs;

  /// No description provided for @supportFaqs.
  ///
  /// In en, this message translates to:
  /// **'FAQs'**
  String get supportFaqs;

  /// No description provided for @supportRaiseTicket.
  ///
  /// In en, this message translates to:
  /// **'Raise a ticket'**
  String get supportRaiseTicket;

  /// No description provided for @supportMyTickets.
  ///
  /// In en, this message translates to:
  /// **'My tickets'**
  String get supportMyTickets;

  /// No description provided for @supportChat.
  ///
  /// In en, this message translates to:
  /// **'Chat with us'**
  String get supportChat;

  /// No description provided for @supportCall.
  ///
  /// In en, this message translates to:
  /// **'Call us'**
  String get supportCall;

  /// No description provided for @supportEmail.
  ///
  /// In en, this message translates to:
  /// **'Email us'**
  String get supportEmail;

  /// No description provided for @searchTitle.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchTitle;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search products'**
  String get searchHint;

  /// No description provided for @searchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get searchNoResults;

  /// No description provided for @searchRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent searches'**
  String get searchRecent;

  /// No description provided for @searchPopular.
  ///
  /// In en, this message translates to:
  /// **'Popular searches'**
  String get searchPopular;

  /// No description provided for @searchResultsFor.
  ///
  /// In en, this message translates to:
  /// **'Results for \"{query}\"'**
  String searchResultsFor(String query);

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @settingsDarkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark mode'**
  String get settingsDarkMode;

  /// No description provided for @settingsLightMode.
  ///
  /// In en, this message translates to:
  /// **'Light mode'**
  String get settingsLightMode;

  /// No description provided for @settingsSystemDefault.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsSystemDefault;

  /// No description provided for @settingsNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotifications;

  /// No description provided for @settingsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy & security'**
  String get settingsPrivacy;

  /// No description provided for @kycStartCta.
  ///
  /// In en, this message translates to:
  /// **'Start verification'**
  String get kycStartCta;

  /// No description provided for @kycSubmitForReview.
  ///
  /// In en, this message translates to:
  /// **'Submit for review'**
  String get kycSubmitForReview;

  /// No description provided for @orderStatusDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get orderStatusDraft;

  /// No description provided for @orderStatusPlaced.
  ///
  /// In en, this message translates to:
  /// **'Placed'**
  String get orderStatusPlaced;

  /// No description provided for @orderStatusReadyForDispatch.
  ///
  /// In en, this message translates to:
  /// **'Ready for dispatch'**
  String get orderStatusReadyForDispatch;

  /// No description provided for @orderStatusRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get orderStatusRejected;

  /// No description provided for @orderStatusReturned.
  ///
  /// In en, this message translates to:
  /// **'Returned'**
  String get orderStatusReturned;

  /// No description provided for @orderStatusPartiallyReturned.
  ///
  /// In en, this message translates to:
  /// **'Partially returned'**
  String get orderStatusPartiallyReturned;

  /// No description provided for @orderStatusFailedDelivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery failed'**
  String get orderStatusFailedDelivery;

  /// No description provided for @payStatusPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get payStatusPaid;

  /// No description provided for @payStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get payStatusFailed;

  /// No description provided for @payStatusRefunded.
  ///
  /// In en, this message translates to:
  /// **'Refunded'**
  String get payStatusRefunded;

  /// No description provided for @verifyStatusNotStarted.
  ///
  /// In en, this message translates to:
  /// **'Not started'**
  String get verifyStatusNotStarted;

  /// No description provided for @verifyStatusDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get verifyStatusDraft;

  /// No description provided for @verifyStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get verifyStatusPending;

  /// No description provided for @verifyStatusUnderReview.
  ///
  /// In en, this message translates to:
  /// **'Under review'**
  String get verifyStatusUnderReview;

  /// No description provided for @verifyStatusApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get verifyStatusApproved;

  /// No description provided for @verifyStatusRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get verifyStatusRejected;

  /// No description provided for @kycNotStarted.
  ///
  /// In en, this message translates to:
  /// **'Not started'**
  String get kycNotStarted;

  /// No description provided for @kycDocAadhaar.
  ///
  /// In en, this message translates to:
  /// **'Aadhaar Card'**
  String get kycDocAadhaar;

  /// No description provided for @kycDocPan.
  ///
  /// In en, this message translates to:
  /// **'PAN Card'**
  String get kycDocPan;

  /// No description provided for @kycDocSelfie.
  ///
  /// In en, this message translates to:
  /// **'Selfie / Video KYC'**
  String get kycDocSelfie;

  /// No description provided for @kycDocResidence.
  ///
  /// In en, this message translates to:
  /// **'Address proof'**
  String get kycDocResidence;

  /// No description provided for @catalogAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get catalogAll;

  /// No description provided for @catalogApplyFilters.
  ///
  /// In en, this message translates to:
  /// **'Apply filters'**
  String get catalogApplyFilters;

  /// No description provided for @catalogBrand.
  ///
  /// In en, this message translates to:
  /// **'Brand'**
  String get catalogBrand;

  /// No description provided for @catalogDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get catalogDescription;

  /// No description provided for @catalogFilter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get catalogFilter;

  /// No description provided for @catalogFilters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get catalogFilters;

  /// No description provided for @catalogGoToCart.
  ///
  /// In en, this message translates to:
  /// **'Go to cart'**
  String get catalogGoToCart;

  /// No description provided for @catalogInStock.
  ///
  /// In en, this message translates to:
  /// **'In stock'**
  String get catalogInStock;

  /// No description provided for @catalogInStockOnly.
  ///
  /// In en, this message translates to:
  /// **'In stock only'**
  String get catalogInStockOnly;

  /// No description provided for @catalogMinDiscount.
  ///
  /// In en, this message translates to:
  /// **'Minimum discount'**
  String get catalogMinDiscount;

  /// No description provided for @catalogNoCategories.
  ///
  /// In en, this message translates to:
  /// **'No categories found'**
  String get catalogNoCategories;

  /// No description provided for @catalogNoProducts.
  ///
  /// In en, this message translates to:
  /// **'No products'**
  String get catalogNoProducts;

  /// No description provided for @catalogNoProductsFound.
  ///
  /// In en, this message translates to:
  /// **'No products found'**
  String get catalogNoProductsFound;

  /// No description provided for @catalogPrice.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get catalogPrice;

  /// No description provided for @catalogProductDetails.
  ///
  /// In en, this message translates to:
  /// **'Product details'**
  String get catalogProductDetails;

  /// No description provided for @catalogProducts.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get catalogProducts;

  /// No description provided for @catalogQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get catalogQuantity;

  /// No description provided for @catalogSearchCategories.
  ///
  /// In en, this message translates to:
  /// **'Search categories'**
  String get catalogSearchCategories;

  /// No description provided for @catalogSelectVariation.
  ///
  /// In en, this message translates to:
  /// **'Select variation'**
  String get catalogSelectVariation;

  /// No description provided for @catalogSort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get catalogSort;

  /// No description provided for @catalogSortBy.
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get catalogSortBy;

  /// No description provided for @catalogSpecifications.
  ///
  /// In en, this message translates to:
  /// **'Specifications'**
  String get catalogSpecifications;

  /// No description provided for @catalogNoProductsInCategory.
  ///
  /// In en, this message translates to:
  /// **'There are no products in this category yet.'**
  String get catalogNoProductsInCategory;

  /// No description provided for @catalogAdjustFilters.
  ///
  /// In en, this message translates to:
  /// **'Try adjusting your filters or search.'**
  String get catalogAdjustFilters;

  /// No description provided for @catalogViewCart.
  ///
  /// In en, this message translates to:
  /// **'View cart'**
  String get catalogViewCart;

  /// No description provided for @catalogYouMayAlsoLike.
  ///
  /// In en, this message translates to:
  /// **'You may also like'**
  String get catalogYouMayAlsoLike;

  /// No description provided for @catalogReviews.
  ///
  /// In en, this message translates to:
  /// **'{count} reviews'**
  String catalogReviews(int count);

  /// No description provided for @catalogBuyNowPayLater.
  ///
  /// In en, this message translates to:
  /// **'Buy now, pay later with zero interest.'**
  String get catalogBuyNowPayLater;

  /// No description provided for @homeExploreCategories.
  ///
  /// In en, this message translates to:
  /// **'Explore categories'**
  String get homeExploreCategories;

  /// No description provided for @homePopularProducts.
  ///
  /// In en, this message translates to:
  /// **'Popular products'**
  String get homePopularProducts;

  /// No description provided for @homeRecentlyOrdered.
  ///
  /// In en, this message translates to:
  /// **'Recently ordered'**
  String get homeRecentlyOrdered;

  /// No description provided for @homeShopNow.
  ///
  /// In en, this message translates to:
  /// **'Shop now'**
  String get homeShopNow;

  /// No description provided for @homeContinueShopping.
  ///
  /// In en, this message translates to:
  /// **'Continue shopping'**
  String get homeContinueShopping;

  /// No description provided for @homeEnableLocation.
  ///
  /// In en, this message translates to:
  /// **'Enable location'**
  String get homeEnableLocation;

  /// No description provided for @homeSpecialSale.
  ///
  /// In en, this message translates to:
  /// **'Special Sale 🔥'**
  String get homeSpecialSale;

  /// No description provided for @homeTapToTrack.
  ///
  /// In en, this message translates to:
  /// **'Tap to track your order'**
  String get homeTapToTrack;

  /// No description provided for @authCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authCreateAccount;

  /// No description provided for @authVerifyContinue.
  ///
  /// In en, this message translates to:
  /// **'Verify & continue'**
  String get authVerifyContinue;

  /// No description provided for @authVerifiedNumber.
  ///
  /// In en, this message translates to:
  /// **'Verified number'**
  String get authVerifiedNumber;

  /// No description provided for @authUseDifferentNumber.
  ///
  /// In en, this message translates to:
  /// **'Use a different number'**
  String get authUseDifferentNumber;

  /// No description provided for @authReferralCode.
  ///
  /// In en, this message translates to:
  /// **'Referral code'**
  String get authReferralCode;

  /// No description provided for @commonOptional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get commonOptional;

  /// No description provided for @authAlmostThere.
  ///
  /// In en, this message translates to:
  /// **'Almost there!'**
  String get authAlmostThere;

  /// No description provided for @authWantCredit.
  ///
  /// In en, this message translates to:
  /// **'Want shop-now-pay-later?'**
  String get authWantCredit;

  /// No description provided for @authTermsOfService.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get authTermsOfService;

  /// No description provided for @authGoToHome.
  ///
  /// In en, this message translates to:
  /// **'Go to home'**
  String get authGoToHome;

  /// No description provided for @billingPurchase.
  ///
  /// In en, this message translates to:
  /// **'Purchase'**
  String get billingPurchase;

  /// No description provided for @billingPenalty.
  ///
  /// In en, this message translates to:
  /// **'Penalty'**
  String get billingPenalty;

  /// No description provided for @billingAdjustment.
  ///
  /// In en, this message translates to:
  /// **'Adjustment'**
  String get billingAdjustment;

  /// No description provided for @billingRefund.
  ///
  /// In en, this message translates to:
  /// **'Refund'**
  String get billingRefund;

  /// No description provided for @billingCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get billingCompleted;

  /// No description provided for @billingReversed.
  ///
  /// In en, this message translates to:
  /// **'Reversed'**
  String get billingReversed;

  /// No description provided for @billingOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get billingOverdue;

  /// No description provided for @billingAssigned.
  ///
  /// In en, this message translates to:
  /// **'Assigned'**
  String get billingAssigned;

  /// No description provided for @billingBankTransfer.
  ///
  /// In en, this message translates to:
  /// **'Bank transfer'**
  String get billingBankTransfer;

  /// No description provided for @billingCashCollection.
  ///
  /// In en, this message translates to:
  /// **'Cash collection'**
  String get billingCashCollection;

  /// No description provided for @billingInvoices.
  ///
  /// In en, this message translates to:
  /// **'Invoices'**
  String get billingInvoices;

  /// No description provided for @billingInvoice.
  ///
  /// In en, this message translates to:
  /// **'Invoice'**
  String get billingInvoice;

  /// No description provided for @billingStatement.
  ///
  /// In en, this message translates to:
  /// **'Statement'**
  String get billingStatement;

  /// No description provided for @billingTransactions.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get billingTransactions;

  /// No description provided for @billingMakePayment.
  ///
  /// In en, this message translates to:
  /// **'Make payment'**
  String get billingMakePayment;

  /// No description provided for @billingEnterAmount.
  ///
  /// In en, this message translates to:
  /// **'Enter amount'**
  String get billingEnterAmount;

  /// No description provided for @billingAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get billingAmount;

  /// No description provided for @billingAmountDue.
  ///
  /// In en, this message translates to:
  /// **'Amount due'**
  String get billingAmountDue;

  /// No description provided for @billingAmountPaid.
  ///
  /// In en, this message translates to:
  /// **'Amount paid'**
  String get billingAmountPaid;

  /// No description provided for @billingPayNow.
  ///
  /// In en, this message translates to:
  /// **'Pay now'**
  String get billingPayNow;

  /// No description provided for @billingDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get billingDate;

  /// No description provided for @billingStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get billingStatus;

  /// No description provided for @billingMethod.
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get billingMethod;

  /// No description provided for @billingReference.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get billingReference;

  /// No description provided for @billingNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes (optional)'**
  String get billingNotes;

  /// No description provided for @billingDownloadReceipt.
  ///
  /// In en, this message translates to:
  /// **'Download receipt'**
  String get billingDownloadReceipt;

  /// No description provided for @commonDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get commonDownload;

  /// No description provided for @billingViewOrder.
  ///
  /// In en, this message translates to:
  /// **'View order'**
  String get billingViewOrder;

  /// No description provided for @billingViewStatement.
  ///
  /// In en, this message translates to:
  /// **'View statement'**
  String get billingViewStatement;

  /// No description provided for @billingRequestCollection.
  ///
  /// In en, this message translates to:
  /// **'Request collection'**
  String get billingRequestCollection;

  /// No description provided for @billingCollections.
  ///
  /// In en, this message translates to:
  /// **'Collections'**
  String get billingCollections;

  /// No description provided for @billingCollected.
  ///
  /// In en, this message translates to:
  /// **'Collected'**
  String get billingCollected;

  /// No description provided for @billingAgent.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get billingAgent;

  /// No description provided for @billingPaymentSuccessful.
  ///
  /// In en, this message translates to:
  /// **'Payment successful'**
  String get billingPaymentSuccessful;

  /// No description provided for @billingTotalOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Total outstanding'**
  String get billingTotalOutstanding;

  /// No description provided for @billingTotalAmountDue.
  ///
  /// In en, this message translates to:
  /// **'Total amount due'**
  String get billingTotalAmountDue;

  /// No description provided for @billingCurrentBill.
  ///
  /// In en, this message translates to:
  /// **'Current bill'**
  String get billingCurrentBill;

  /// No description provided for @billingRecentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get billingRecentActivity;

  /// No description provided for @billingBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Breakdown'**
  String get billingBreakdown;

  /// No description provided for @billingPrincipal.
  ///
  /// In en, this message translates to:
  /// **'Principal'**
  String get billingPrincipal;

  /// No description provided for @billingInterest.
  ///
  /// In en, this message translates to:
  /// **'Interest'**
  String get billingInterest;

  /// No description provided for @billingLateFee.
  ///
  /// In en, this message translates to:
  /// **'Late fee'**
  String get billingLateFee;

  /// No description provided for @billingInvoiceNumber.
  ///
  /// In en, this message translates to:
  /// **'Invoice number'**
  String get billingInvoiceNumber;

  /// No description provided for @billingInvoiceDate.
  ///
  /// In en, this message translates to:
  /// **'Invoice date'**
  String get billingInvoiceDate;

  /// No description provided for @billingCreditSummary.
  ///
  /// In en, this message translates to:
  /// **'Credit summary'**
  String get billingCreditSummary;

  /// No description provided for @billingBackToDashboard.
  ///
  /// In en, this message translates to:
  /// **'Back to dashboard'**
  String get billingBackToDashboard;

  /// No description provided for @billingNoInvoices.
  ///
  /// In en, this message translates to:
  /// **'No invoices yet'**
  String get billingNoInvoices;

  /// No description provided for @billingNoPayments.
  ///
  /// In en, this message translates to:
  /// **'No payments yet'**
  String get billingNoPayments;

  /// No description provided for @billingNoStatements.
  ///
  /// In en, this message translates to:
  /// **'No statements yet'**
  String get billingNoStatements;

  /// No description provided for @billingNoCollections.
  ///
  /// In en, this message translates to:
  /// **'No collection requests'**
  String get billingNoCollections;

  /// No description provided for @billingNoTransactions.
  ///
  /// In en, this message translates to:
  /// **'No transactions yet'**
  String get billingNoTransactions;

  /// No description provided for @billingAllCaughtUp.
  ///
  /// In en, this message translates to:
  /// **'All caught up'**
  String get billingAllCaughtUp;

  /// No description provided for @billingNoPendingDues.
  ///
  /// In en, this message translates to:
  /// **'You have no pending dues right now.'**
  String get billingNoPendingDues;

  /// No description provided for @billingInvoicesAppearHere.
  ///
  /// In en, this message translates to:
  /// **'Invoices for your credit orders will appear here.'**
  String get billingInvoicesAppearHere;

  /// No description provided for @billingStatementsAppearHere.
  ///
  /// In en, this message translates to:
  /// **'Your billing statements will appear here.'**
  String get billingStatementsAppearHere;

  /// No description provided for @billingRepaymentsAppearHere.
  ///
  /// In en, this message translates to:
  /// **'Your repayments will show up here.'**
  String get billingRepaymentsAppearHere;

  /// No description provided for @billingRepaymentRecorded.
  ///
  /// In en, this message translates to:
  /// **'Your repayment has been recorded.'**
  String get billingRepaymentRecorded;

  /// No description provided for @billingSecurePayments.
  ///
  /// In en, this message translates to:
  /// **'100% secure payments'**
  String get billingSecurePayments;

  /// No description provided for @billingInvoiceNotFound.
  ///
  /// In en, this message translates to:
  /// **'Invoice not found'**
  String get billingInvoiceNotFound;

  /// No description provided for @billingStatementNotFound.
  ///
  /// In en, this message translates to:
  /// **'Statement not found'**
  String get billingStatementNotFound;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// No description provided for @profileQuickAccess.
  ///
  /// In en, this message translates to:
  /// **'Quick access'**
  String get profileQuickAccess;

  /// No description provided for @profileCreditCenter.
  ///
  /// In en, this message translates to:
  /// **'Credit center'**
  String get profileCreditCenter;

  /// No description provided for @profileRecentOrders.
  ///
  /// In en, this message translates to:
  /// **'Recent orders'**
  String get profileRecentOrders;

  /// No description provided for @profileRecentPayments.
  ///
  /// In en, this message translates to:
  /// **'Recent payments'**
  String get profileRecentPayments;

  /// No description provided for @profileNoOrders.
  ///
  /// In en, this message translates to:
  /// **'No orders yet'**
  String get profileNoOrders;

  /// No description provided for @profileNotSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Not signed in'**
  String get profileNotSignedIn;

  /// No description provided for @profileSignInPrompt.
  ///
  /// In en, this message translates to:
  /// **'Sign in to view and edit your profile.'**
  String get profileSignInPrompt;

  /// No description provided for @profileSignInCreate.
  ///
  /// In en, this message translates to:
  /// **'Sign in / Create account'**
  String get profileSignInCreate;

  /// No description provided for @profilePayDue.
  ///
  /// In en, this message translates to:
  /// **'Pay due'**
  String get profilePayDue;

  /// No description provided for @profileManageAddresses.
  ///
  /// In en, this message translates to:
  /// **'Manage addresses'**
  String get profileManageAddresses;

  /// No description provided for @profileMyReturns.
  ///
  /// In en, this message translates to:
  /// **'My returns'**
  String get profileMyReturns;

  /// No description provided for @profileRewards.
  ///
  /// In en, this message translates to:
  /// **'Rewards'**
  String get profileRewards;

  /// No description provided for @profileReferEarn.
  ///
  /// In en, this message translates to:
  /// **'Refer & Earn'**
  String get profileReferEarn;

  /// No description provided for @profileOffersRewards.
  ///
  /// In en, this message translates to:
  /// **'Offers & rewards'**
  String get profileOffersRewards;

  /// No description provided for @profileViewOffers.
  ///
  /// In en, this message translates to:
  /// **'View offers'**
  String get profileViewOffers;

  /// No description provided for @profileFaqHelp.
  ///
  /// In en, this message translates to:
  /// **'FAQ & Help'**
  String get profileFaqHelp;

  /// No description provided for @profileGender.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get profileGender;

  /// No description provided for @profileDob.
  ///
  /// In en, this message translates to:
  /// **'Date of birth'**
  String get profileDob;

  /// No description provided for @profileChangeNumberNote.
  ///
  /// In en, this message translates to:
  /// **'To change your verified number, contact support.'**
  String get profileChangeNumberNote;

  /// No description provided for @profileKycStatus.
  ///
  /// In en, this message translates to:
  /// **'KYC status'**
  String get profileKycStatus;

  /// No description provided for @profileFamilyInfo.
  ///
  /// In en, this message translates to:
  /// **'Family information'**
  String get profileFamilyInfo;

  /// No description provided for @profileHouseholdMembers.
  ///
  /// In en, this message translates to:
  /// **'Household members'**
  String get profileHouseholdMembers;

  /// No description provided for @profileAddMember.
  ///
  /// In en, this message translates to:
  /// **'Add member'**
  String get profileAddMember;

  /// No description provided for @profileInviteMember.
  ///
  /// In en, this message translates to:
  /// **'Invite family member'**
  String get profileInviteMember;

  /// No description provided for @profileRemoveMember.
  ///
  /// In en, this message translates to:
  /// **'Remove member'**
  String get profileRemoveMember;

  /// No description provided for @profileRelationship.
  ///
  /// In en, this message translates to:
  /// **'Relationship'**
  String get profileRelationship;

  /// No description provided for @profileActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get profileActive;

  /// No description provided for @profileCouldNotLoadPayments.
  ///
  /// In en, this message translates to:
  /// **'Could not load payments.'**
  String get profileCouldNotLoadPayments;

  /// No description provided for @creditAmountToPay.
  ///
  /// In en, this message translates to:
  /// **'Amount to pay'**
  String get creditAmountToPay;

  /// No description provided for @creditProceedToPayment.
  ///
  /// In en, this message translates to:
  /// **'Proceed to payment'**
  String get creditProceedToPayment;

  /// No description provided for @creditTxnSuccess.
  ///
  /// In en, this message translates to:
  /// **'Your transaction was completed successfully.'**
  String get creditTxnSuccess;

  /// No description provided for @creditTransactionId.
  ///
  /// In en, this message translates to:
  /// **'Transaction ID'**
  String get creditTransactionId;

  /// No description provided for @creditNextPaymentDue.
  ///
  /// In en, this message translates to:
  /// **'Next payment due'**
  String get creditNextPaymentDue;

  /// No description provided for @creditPayOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Pay outstanding'**
  String get creditPayOutstanding;

  /// No description provided for @creditHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get creditHistory;

  /// No description provided for @creditRemaining.
  ///
  /// In en, this message translates to:
  /// **'Remaining credit'**
  String get creditRemaining;

  /// No description provided for @creditPurchases.
  ///
  /// In en, this message translates to:
  /// **'Purchases'**
  String get creditPurchases;

  /// No description provided for @creditPaymentsMade.
  ///
  /// In en, this message translates to:
  /// **'Payments made'**
  String get creditPaymentsMade;

  /// No description provided for @creditAppUnderReview.
  ///
  /// In en, this message translates to:
  /// **'Application under review'**
  String get creditAppUnderReview;

  /// No description provided for @creditAppNotApproved.
  ///
  /// In en, this message translates to:
  /// **'Application not approved'**
  String get creditAppNotApproved;

  /// No description provided for @creditScoreIncreased.
  ///
  /// In en, this message translates to:
  /// **'VS Score increased'**
  String get creditScoreIncreased;

  /// No description provided for @creditGreatBehavior.
  ///
  /// In en, this message translates to:
  /// **'Great financial behavior!'**
  String get creditGreatBehavior;

  /// No description provided for @creditFinancialStatusUpdated.
  ///
  /// In en, this message translates to:
  /// **'Financial status updated'**
  String get creditFinancialStatusUpdated;

  /// No description provided for @creditTransactionDetails.
  ///
  /// In en, this message translates to:
  /// **'Transaction details'**
  String get creditTransactionDetails;

  /// No description provided for @checkoutViewOrders.
  ///
  /// In en, this message translates to:
  /// **'View orders'**
  String get checkoutViewOrders;

  /// No description provided for @checkoutChangeAddress.
  ///
  /// In en, this message translates to:
  /// **'Change address'**
  String get checkoutChangeAddress;

  /// No description provided for @checkoutAmountPayable.
  ///
  /// In en, this message translates to:
  /// **'Amount payable'**
  String get checkoutAmountPayable;

  /// No description provided for @checkoutInclusiveCharges.
  ///
  /// In en, this message translates to:
  /// **'Inclusive of all charges'**
  String get checkoutInclusiveCharges;

  /// No description provided for @checkoutSelectOption.
  ///
  /// In en, this message translates to:
  /// **'Select option'**
  String get checkoutSelectOption;

  /// No description provided for @checkoutOnlinePayment.
  ///
  /// In en, this message translates to:
  /// **'Online payment'**
  String get checkoutOnlinePayment;

  /// No description provided for @checkoutInstantPayment.
  ///
  /// In en, this message translates to:
  /// **'Instant payment'**
  String get checkoutInstantPayment;

  /// No description provided for @checkoutPayOnDelivery.
  ///
  /// In en, this message translates to:
  /// **'Pay on delivery'**
  String get checkoutPayOnDelivery;

  /// No description provided for @checkoutPayOnArrival.
  ///
  /// In en, this message translates to:
  /// **'Pay when your order arrives'**
  String get checkoutPayOnArrival;

  /// No description provided for @checkoutBuyNowPayLater.
  ///
  /// In en, this message translates to:
  /// **'Buy now, pay later'**
  String get checkoutBuyNowPayLater;

  /// No description provided for @checkoutUpiCardsNetbanking.
  ///
  /// In en, this message translates to:
  /// **'UPI, cards & net banking'**
  String get checkoutUpiCardsNetbanking;

  /// No description provided for @checkoutCreditDebitCard.
  ///
  /// In en, this message translates to:
  /// **'Credit / Debit card'**
  String get checkoutCreditDebitCard;

  /// No description provided for @checkoutChooseRepaymentPlan.
  ///
  /// In en, this message translates to:
  /// **'Choose a repayment plan'**
  String get checkoutChooseRepaymentPlan;

  /// No description provided for @checkoutPayoutDate.
  ///
  /// In en, this message translates to:
  /// **'Payout date'**
  String get checkoutPayoutDate;

  /// No description provided for @checkoutSecuredByRazorpay.
  ///
  /// In en, this message translates to:
  /// **'Payments secured by Razorpay.'**
  String get checkoutSecuredByRazorpay;

  /// No description provided for @checkoutOrderConfirmedBody.
  ///
  /// In en, this message translates to:
  /// **'Thank you! Your order is confirmed and being prepared.'**
  String get checkoutOrderConfirmedBody;

  /// No description provided for @checkoutAgreeTerms.
  ///
  /// In en, this message translates to:
  /// **'By placing this order, you agree to our Terms & Conditions and Return Policy.'**
  String get checkoutAgreeTerms;

  /// No description provided for @checkoutEnterCoupon.
  ///
  /// In en, this message translates to:
  /// **'Enter a coupon code'**
  String get checkoutEnterCoupon;

  /// No description provided for @checkoutCouponValidateFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not validate coupon'**
  String get checkoutCouponValidateFailed;

  /// No description provided for @kycDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'KYC details'**
  String get kycDetailsTitle;

  /// No description provided for @kycVerificationTitle.
  ///
  /// In en, this message translates to:
  /// **'KYC verification'**
  String get kycVerificationTitle;

  /// No description provided for @kycVerificationStatus.
  ///
  /// In en, this message translates to:
  /// **'Verification status'**
  String get kycVerificationStatus;

  /// No description provided for @kycActionNeeded.
  ///
  /// In en, this message translates to:
  /// **'Action needed'**
  String get kycActionNeeded;

  /// No description provided for @kycSubmittedDocs.
  ///
  /// In en, this message translates to:
  /// **'Submitted documents'**
  String get kycSubmittedDocs;

  /// No description provided for @kycNoDocuments.
  ///
  /// In en, this message translates to:
  /// **'No documents on file yet.'**
  String get kycNoDocuments;

  /// No description provided for @kycNeedHelp.
  ///
  /// In en, this message translates to:
  /// **'Need help with KYC?'**
  String get kycNeedHelp;

  /// No description provided for @kycDataSecured.
  ///
  /// In en, this message translates to:
  /// **'Your data is secured'**
  String get kycDataSecured;

  /// No description provided for @kycChecklist.
  ///
  /// In en, this message translates to:
  /// **'Checklist'**
  String get kycChecklist;

  /// No description provided for @kycReason.
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason}'**
  String kycReason(String reason);

  /// No description provided for @verifyTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify your identity'**
  String get verifyTitle;

  /// No description provided for @verifyIdentityDocs.
  ///
  /// In en, this message translates to:
  /// **'Identity documents'**
  String get verifyIdentityDocs;

  /// No description provided for @verifyIdentityVerification.
  ///
  /// In en, this message translates to:
  /// **'Identity verification'**
  String get verifyIdentityVerification;

  /// No description provided for @verifyAadhaar.
  ///
  /// In en, this message translates to:
  /// **'Aadhaar verification'**
  String get verifyAadhaar;

  /// No description provided for @verifyPan.
  ///
  /// In en, this message translates to:
  /// **'PAN verification'**
  String get verifyPan;

  /// No description provided for @verifyFace.
  ///
  /// In en, this message translates to:
  /// **'Face verification'**
  String get verifyFace;

  /// No description provided for @verifySelfie.
  ///
  /// In en, this message translates to:
  /// **'Selfie verification'**
  String get verifySelfie;

  /// No description provided for @verifyLocation.
  ///
  /// In en, this message translates to:
  /// **'Location verification'**
  String get verifyLocation;

  /// No description provided for @verifyResidence.
  ///
  /// In en, this message translates to:
  /// **'Residence verification'**
  String get verifyResidence;

  /// No description provided for @verifyCreditApp.
  ///
  /// In en, this message translates to:
  /// **'Credit application'**
  String get verifyCreditApp;

  /// No description provided for @verifyCreditAssessment.
  ///
  /// In en, this message translates to:
  /// **'Credit assessment'**
  String get verifyCreditAssessment;

  /// No description provided for @verifyReviewApp.
  ///
  /// In en, this message translates to:
  /// **'Review your application'**
  String get verifyReviewApp;

  /// No description provided for @verifyPersonalDetails.
  ///
  /// In en, this message translates to:
  /// **'Personal details'**
  String get verifyPersonalDetails;

  /// No description provided for @verifyEmploymentDetails.
  ///
  /// In en, this message translates to:
  /// **'Employment details'**
  String get verifyEmploymentDetails;

  /// No description provided for @verifyIncomeInfo.
  ///
  /// In en, this message translates to:
  /// **'Income information'**
  String get verifyIncomeInfo;

  /// No description provided for @verifyFinancialInfo.
  ///
  /// In en, this message translates to:
  /// **'Financial information'**
  String get verifyFinancialInfo;

  /// No description provided for @verifyAddressDetails.
  ///
  /// In en, this message translates to:
  /// **'Address details'**
  String get verifyAddressDetails;

  /// No description provided for @verifyDocuments.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get verifyDocuments;

  /// No description provided for @verifyUploadAadhaar.
  ///
  /// In en, this message translates to:
  /// **'Upload Aadhaar'**
  String get verifyUploadAadhaar;

  /// No description provided for @verifyUploadPan.
  ///
  /// In en, this message translates to:
  /// **'Upload PAN photo'**
  String get verifyUploadPan;

  /// No description provided for @verifyUploadDocs.
  ///
  /// In en, this message translates to:
  /// **'Upload documents'**
  String get verifyUploadDocs;

  /// No description provided for @verifyUploadContinue.
  ///
  /// In en, this message translates to:
  /// **'Upload & continue'**
  String get verifyUploadContinue;

  /// No description provided for @verifyCapture.
  ///
  /// In en, this message translates to:
  /// **'Capture'**
  String get verifyCapture;

  /// No description provided for @verifyRetake.
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get verifyRetake;

  /// No description provided for @verifyCamera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get verifyCamera;

  /// No description provided for @verifyGallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get verifyGallery;

  /// No description provided for @verifyChooseGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get verifyChooseGallery;

  /// No description provided for @verifyStartingCamera.
  ///
  /// In en, this message translates to:
  /// **'Starting camera…'**
  String get verifyStartingCamera;

  /// No description provided for @verifyCameraNeeded.
  ///
  /// In en, this message translates to:
  /// **'Camera access needed'**
  String get verifyCameraNeeded;

  /// No description provided for @verifyUploaded.
  ///
  /// In en, this message translates to:
  /// **'Uploaded'**
  String get verifyUploaded;

  /// No description provided for @verifyUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Upload failed'**
  String get verifyUploadFailed;

  /// No description provided for @verifySaveDraft.
  ///
  /// In en, this message translates to:
  /// **'Save draft'**
  String get verifySaveDraft;

  /// No description provided for @verifySubmitApp.
  ///
  /// In en, this message translates to:
  /// **'Submit application'**
  String get verifySubmitApp;

  /// No description provided for @verifyReviewBeforeSubmit.
  ///
  /// In en, this message translates to:
  /// **'Review each section before submitting for approval.'**
  String get verifyReviewBeforeSubmit;

  /// No description provided for @verifyAppSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Application submitted!'**
  String get verifyAppSubmitted;

  /// No description provided for @verifyAppReceived.
  ///
  /// In en, this message translates to:
  /// **'We received your application'**
  String get verifyAppReceived;

  /// No description provided for @verifyTeamVerifying.
  ///
  /// In en, this message translates to:
  /// **'Our team is verifying your details'**
  String get verifyTeamVerifying;

  /// No description provided for @verifyPending.
  ///
  /// In en, this message translates to:
  /// **'Verification pending'**
  String get verifyPending;

  /// No description provided for @verifyTrackApp.
  ///
  /// In en, this message translates to:
  /// **'Track application'**
  String get verifyTrackApp;

  /// No description provided for @verifyReapply.
  ///
  /// In en, this message translates to:
  /// **'Reapply'**
  String get verifyReapply;

  /// No description provided for @verifyMonthlyIncome.
  ///
  /// In en, this message translates to:
  /// **'Monthly income'**
  String get verifyMonthlyIncome;

  /// No description provided for @verifyOccupation.
  ///
  /// In en, this message translates to:
  /// **'Occupation'**
  String get verifyOccupation;

  /// No description provided for @verifyHouseType.
  ///
  /// In en, this message translates to:
  /// **'House type'**
  String get verifyHouseType;

  /// No description provided for @verifyOwnership.
  ///
  /// In en, this message translates to:
  /// **'Ownership'**
  String get verifyOwnership;

  /// No description provided for @verifyFamilyMembers.
  ///
  /// In en, this message translates to:
  /// **'Family members'**
  String get verifyFamilyMembers;

  /// No description provided for @verifyRequestedLimit.
  ///
  /// In en, this message translates to:
  /// **'Requested limit'**
  String get verifyRequestedLimit;

  /// No description provided for @verifyRequestedCreditLimit.
  ///
  /// In en, this message translates to:
  /// **'Requested credit limit'**
  String get verifyRequestedCreditLimit;

  /// No description provided for @verifyApprovedLimit.
  ///
  /// In en, this message translates to:
  /// **'Approved credit limit'**
  String get verifyApprovedLimit;

  /// No description provided for @verifyPotentialLimit.
  ///
  /// In en, this message translates to:
  /// **'Potential credit limit'**
  String get verifyPotentialLimit;

  /// No description provided for @verifyAadhaarNumber.
  ///
  /// In en, this message translates to:
  /// **'12-digit Aadhaar number'**
  String get verifyAadhaarNumber;

  /// No description provided for @verifyPanNumber.
  ///
  /// In en, this message translates to:
  /// **'PAN number'**
  String get verifyPanNumber;

  /// No description provided for @verifyAvailableNow.
  ///
  /// In en, this message translates to:
  /// **'Available now'**
  String get verifyAvailableNow;

  /// No description provided for @verifyApplicationId.
  ///
  /// In en, this message translates to:
  /// **'Application ID'**
  String get verifyApplicationId;

  /// No description provided for @verifySubmittedOn.
  ///
  /// In en, this message translates to:
  /// **'Submitted on'**
  String get verifySubmittedOn;

  /// No description provided for @verifyExpectedReview.
  ///
  /// In en, this message translates to:
  /// **'Expected review'**
  String get verifyExpectedReview;

  /// No description provided for @verifyCurrentStatus.
  ///
  /// In en, this message translates to:
  /// **'Current status'**
  String get verifyCurrentStatus;

  /// No description provided for @verifyReason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get verifyReason;

  /// No description provided for @verifyWhyNeed.
  ///
  /// In en, this message translates to:
  /// **'Why we need this'**
  String get verifyWhyNeed;

  /// No description provided for @verifyPhotoRequirements.
  ///
  /// In en, this message translates to:
  /// **'Photo requirements'**
  String get verifyPhotoRequirements;

  /// No description provided for @verifyFaceVisible.
  ///
  /// In en, this message translates to:
  /// **'Ensure your face is clearly visible.'**
  String get verifyFaceVisible;

  /// No description provided for @verifyPhotoFormat.
  ///
  /// In en, this message translates to:
  /// **'JPG or PNG, up to 5 MB'**
  String get verifyPhotoFormat;

  /// No description provided for @verifySecureEncrypted.
  ///
  /// In en, this message translates to:
  /// **'100% secure & encrypted'**
  String get verifySecureEncrypted;

  /// No description provided for @verifyStepOf.
  ///
  /// In en, this message translates to:
  /// **'Step {step} of {total}'**
  String verifyStepOf(int step, int total);

  /// No description provided for @supportHowCanWeHelp.
  ///
  /// In en, this message translates to:
  /// **'How can we help you today?'**
  String get supportHowCanWeHelp;

  /// No description provided for @supportQuickHelp.
  ///
  /// In en, this message translates to:
  /// **'Quick help topics'**
  String get supportQuickHelp;

  /// No description provided for @supportSearchFaqs.
  ///
  /// In en, this message translates to:
  /// **'Search FAQs'**
  String get supportSearchFaqs;

  /// No description provided for @supportNewConversation.
  ///
  /// In en, this message translates to:
  /// **'New conversation'**
  String get supportNewConversation;

  /// No description provided for @supportOpenConversation.
  ///
  /// In en, this message translates to:
  /// **'Open conversation'**
  String get supportOpenConversation;

  /// No description provided for @supportStartConversation.
  ///
  /// In en, this message translates to:
  /// **'Start a conversation'**
  String get supportStartConversation;

  /// No description provided for @supportNoMessages.
  ///
  /// In en, this message translates to:
  /// **'No messages yet'**
  String get supportNoMessages;

  /// No description provided for @supportNoTickets.
  ///
  /// In en, this message translates to:
  /// **'No tickets here'**
  String get supportNoTickets;

  /// No description provided for @supportNoTicketsCategory.
  ///
  /// In en, this message translates to:
  /// **'You have no tickets in this category yet.'**
  String get supportNoTicketsCategory;

  /// No description provided for @supportTicketDetails.
  ///
  /// In en, this message translates to:
  /// **'Ticket details'**
  String get supportTicketDetails;

  /// No description provided for @supportTicketProgress.
  ///
  /// In en, this message translates to:
  /// **'Ticket progress'**
  String get supportTicketProgress;

  /// No description provided for @supportIssueCategory.
  ///
  /// In en, this message translates to:
  /// **'Issue category'**
  String get supportIssueCategory;

  /// No description provided for @supportIssueDescription.
  ///
  /// In en, this message translates to:
  /// **'Issue description'**
  String get supportIssueDescription;

  /// No description provided for @supportPriorityLevel.
  ///
  /// In en, this message translates to:
  /// **'Priority level'**
  String get supportPriorityLevel;

  /// No description provided for @supportSelectCategory.
  ///
  /// In en, this message translates to:
  /// **'Select an issue category'**
  String get supportSelectCategory;

  /// No description provided for @supportDescribeIssue.
  ///
  /// In en, this message translates to:
  /// **'Please describe your issue in detail…'**
  String get supportDescribeIssue;

  /// No description provided for @supportRelatedOrder.
  ///
  /// In en, this message translates to:
  /// **'Related order (optional)'**
  String get supportRelatedOrder;

  /// No description provided for @supportAttachments.
  ///
  /// In en, this message translates to:
  /// **'Attachments (optional)'**
  String get supportAttachments;

  /// No description provided for @supportUploadFile.
  ///
  /// In en, this message translates to:
  /// **'Upload file'**
  String get supportUploadFile;

  /// No description provided for @supportSubmitTicket.
  ///
  /// In en, this message translates to:
  /// **'Submit ticket'**
  String get supportSubmitTicket;

  /// No description provided for @supportAddReply.
  ///
  /// In en, this message translates to:
  /// **'Add reply'**
  String get supportAddReply;

  /// No description provided for @supportTypeMessage.
  ///
  /// In en, this message translates to:
  /// **'Type your message…'**
  String get supportTypeMessage;

  /// No description provided for @supportSendToStart.
  ///
  /// In en, this message translates to:
  /// **'Send a message to start the conversation.'**
  String get supportSendToStart;

  /// No description provided for @supportCloseTicket.
  ///
  /// In en, this message translates to:
  /// **'Close ticket'**
  String get supportCloseTicket;

  /// No description provided for @supportStillNeedHelp.
  ///
  /// In en, this message translates to:
  /// **'Still need help?'**
  String get supportStillNeedHelp;

  /// No description provided for @supportLiveChat.
  ///
  /// In en, this message translates to:
  /// **'Live chat'**
  String get supportLiveChat;

  /// No description provided for @supportCallSupport.
  ///
  /// In en, this message translates to:
  /// **'Call support'**
  String get supportCallSupport;

  /// No description provided for @supportContactInfo.
  ///
  /// In en, this message translates to:
  /// **'Contact information'**
  String get supportContactInfo;

  /// No description provided for @supportRegisteredEmail.
  ///
  /// In en, this message translates to:
  /// **'Registered email'**
  String get supportRegisteredEmail;

  /// No description provided for @supportRegisteredMobile.
  ///
  /// In en, this message translates to:
  /// **'Registered mobile'**
  String get supportRegisteredMobile;

  /// No description provided for @supportResponseTime.
  ///
  /// In en, this message translates to:
  /// **'Estimated response time'**
  String get supportResponseTime;

  /// No description provided for @supportTypicalReply.
  ///
  /// In en, this message translates to:
  /// **'We typically reply within 2 hours'**
  String get supportTypicalReply;

  /// No description provided for @supportCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get supportCategory;

  /// No description provided for @supportCreated.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get supportCreated;

  /// No description provided for @supportStatusOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get supportStatusOpen;

  /// No description provided for @supportStatusClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get supportStatusClosed;

  /// No description provided for @supportStatusResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get supportStatusResolved;

  /// No description provided for @supportStatusInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get supportStatusInProgress;

  /// No description provided for @supportPriorityHigh.
  ///
  /// In en, this message translates to:
  /// **'High priority'**
  String get supportPriorityHigh;

  /// No description provided for @commonStartShopping.
  ///
  /// In en, this message translates to:
  /// **'Start shopping'**
  String get commonStartShopping;

  /// No description provided for @commonBuyNow.
  ///
  /// In en, this message translates to:
  /// **'Buy now'**
  String get commonBuyNow;

  /// No description provided for @commonShareVia.
  ///
  /// In en, this message translates to:
  /// **'Share via'**
  String get commonShareVia;

  /// No description provided for @offersAndDeals.
  ///
  /// In en, this message translates to:
  /// **'Offers & deals'**
  String get offersAndDeals;

  /// No description provided for @offersCouponsTitle.
  ///
  /// In en, this message translates to:
  /// **'Coupons & offers'**
  String get offersCouponsTitle;

  /// No description provided for @offersActiveCoupons.
  ///
  /// In en, this message translates to:
  /// **'Active coupons'**
  String get offersActiveCoupons;

  /// No description provided for @offersAvailableCoupons.
  ///
  /// In en, this message translates to:
  /// **'Available coupons'**
  String get offersAvailableCoupons;

  /// No description provided for @offersCashback.
  ///
  /// In en, this message translates to:
  /// **'Cashback offers'**
  String get offersCashback;

  /// No description provided for @offersCombo.
  ///
  /// In en, this message translates to:
  /// **'Combo offers'**
  String get offersCombo;

  /// No description provided for @offersFlashDeals.
  ///
  /// In en, this message translates to:
  /// **'Flash deals'**
  String get offersFlashDeals;

  /// No description provided for @offersTopDeals.
  ///
  /// In en, this message translates to:
  /// **'Top deals'**
  String get offersTopDeals;

  /// No description provided for @offersSpecialDeals.
  ///
  /// In en, this message translates to:
  /// **'Special deals'**
  String get offersSpecialDeals;

  /// No description provided for @offersExpiringSoon.
  ///
  /// In en, this message translates to:
  /// **'Expiring soon'**
  String get offersExpiringSoon;

  /// No description provided for @offersLimitedTime.
  ///
  /// In en, this message translates to:
  /// **'Limited time'**
  String get offersLimitedTime;

  /// No description provided for @offersSellingFast.
  ///
  /// In en, this message translates to:
  /// **'Selling fast'**
  String get offersSellingFast;

  /// No description provided for @offersHowToUse.
  ///
  /// In en, this message translates to:
  /// **'How to use a coupon'**
  String get offersHowToUse;

  /// No description provided for @offersCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get offersCopy;

  /// No description provided for @offersNoCoupons.
  ///
  /// In en, this message translates to:
  /// **'No coupons available'**
  String get offersNoCoupons;

  /// No description provided for @offersNoCouponsYet.
  ///
  /// In en, this message translates to:
  /// **'No coupons yet'**
  String get offersNoCouponsYet;

  /// No description provided for @offersNoDeals.
  ///
  /// In en, this message translates to:
  /// **'No deals right now'**
  String get offersNoDeals;

  /// No description provided for @offersLoadingDeals.
  ///
  /// In en, this message translates to:
  /// **'Loading deals…'**
  String get offersLoadingDeals;

  /// No description provided for @offersCouponsAppearHere.
  ///
  /// In en, this message translates to:
  /// **'Coupons you collect will appear here.'**
  String get offersCouponsAppearHere;

  /// No description provided for @offersCheckBackSoon.
  ///
  /// In en, this message translates to:
  /// **'Check back soon for fresh savings.'**
  String get offersCheckBackSoon;

  /// No description provided for @offersSaveMore.
  ///
  /// In en, this message translates to:
  /// **'Save more on every order'**
  String get offersSaveMore;

  /// No description provided for @offersCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get offersCodeCopied;

  /// No description provided for @cartBuyOnCredit.
  ///
  /// In en, this message translates to:
  /// **'Buy on Credit'**
  String get cartBuyOnCredit;

  /// No description provided for @cartPayLaterZeroInterest.
  ///
  /// In en, this message translates to:
  /// **'Pay later with zero interest.'**
  String get cartPayLaterZeroInterest;

  /// No description provided for @cartPurchaseMode.
  ///
  /// In en, this message translates to:
  /// **'Purchase mode'**
  String get cartPurchaseMode;

  /// No description provided for @cartSignInToCheckout.
  ///
  /// In en, this message translates to:
  /// **'Sign in to checkout'**
  String get cartSignInToCheckout;

  /// No description provided for @cartKeepBrowsing.
  ///
  /// In en, this message translates to:
  /// **'Keep browsing'**
  String get cartKeepBrowsing;

  /// No description provided for @cartItemsNeedAttention.
  ///
  /// In en, this message translates to:
  /// **'Some items need attention before checkout.'**
  String get cartItemsNeedAttention;

  /// No description provided for @wishlistTitle.
  ///
  /// In en, this message translates to:
  /// **'Wishlist'**
  String get wishlistTitle;

  /// No description provided for @wishlistSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved items'**
  String get wishlistSaved;

  /// No description provided for @wishlistEmpty.
  ///
  /// In en, this message translates to:
  /// **'Your wishlist is empty'**
  String get wishlistEmpty;

  /// No description provided for @wishlistEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Tap the heart on any product to save it for later.'**
  String get wishlistEmptyBody;

  /// No description provided for @wishlistNoMatch.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches this filter.'**
  String get wishlistNoMatch;

  /// No description provided for @wishlistTotalValue.
  ///
  /// In en, this message translates to:
  /// **'Total value of wishlist'**
  String get wishlistTotalValue;

  /// No description provided for @wishlistPriceDropAlerts.
  ///
  /// In en, this message translates to:
  /// **'Price drop alerts'**
  String get wishlistPriceDropAlerts;

  /// No description provided for @wishlistViewProduct.
  ///
  /// In en, this message translates to:
  /// **'View product'**
  String get wishlistViewProduct;

  /// No description provided for @searchFiltersAndSort.
  ///
  /// In en, this message translates to:
  /// **'Filters & sort'**
  String get searchFiltersAndSort;

  /// No description provided for @searchPopularity.
  ///
  /// In en, this message translates to:
  /// **'Popularity'**
  String get searchPopularity;

  /// No description provided for @searchPriceLowHigh.
  ///
  /// In en, this message translates to:
  /// **'Price: Low to High'**
  String get searchPriceLowHigh;

  /// No description provided for @searchRating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get searchRating;

  /// No description provided for @searchTopRated.
  ///
  /// In en, this message translates to:
  /// **'Top rated'**
  String get searchTopRated;

  /// No description provided for @searchTopRated4Star.
  ///
  /// In en, this message translates to:
  /// **'Top rated (4★ and above)'**
  String get searchTopRated4Star;

  /// No description provided for @settingsAccountSettings.
  ///
  /// In en, this message translates to:
  /// **'Account settings'**
  String get settingsAccountSettings;

  /// No description provided for @settingsAppPreferences.
  ///
  /// In en, this message translates to:
  /// **'App preferences'**
  String get settingsAppPreferences;

  /// No description provided for @settingsSecuritySettings.
  ///
  /// In en, this message translates to:
  /// **'Security settings'**
  String get settingsSecuritySettings;

  /// No description provided for @settingsCreditSettings.
  ///
  /// In en, this message translates to:
  /// **'Credit settings'**
  String get settingsCreditSettings;

  /// No description provided for @settingsSupportLegal.
  ///
  /// In en, this message translates to:
  /// **'Support & legal'**
  String get settingsSupportLegal;

  /// No description provided for @settingsEmergencyContacts.
  ///
  /// In en, this message translates to:
  /// **'Emergency contacts'**
  String get settingsEmergencyContacts;

  /// No description provided for @settingsNotificationPrefs.
  ///
  /// In en, this message translates to:
  /// **'Notification preferences'**
  String get settingsNotificationPrefs;

  /// No description provided for @settingsLocationPermissions.
  ///
  /// In en, this message translates to:
  /// **'Location permissions'**
  String get settingsLocationPermissions;

  /// No description provided for @settingsChangeMpin.
  ///
  /// In en, this message translates to:
  /// **'Change MPIN'**
  String get settingsChangeMpin;

  /// No description provided for @settingsChangePassword.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get settingsChangePassword;

  /// No description provided for @settingsManageDevices.
  ///
  /// In en, this message translates to:
  /// **'Manage devices'**
  String get settingsManageDevices;

  /// No description provided for @settingsLoginActivity.
  ///
  /// In en, this message translates to:
  /// **'Login activity'**
  String get settingsLoginActivity;

  /// No description provided for @settingsBiometricLogin.
  ///
  /// In en, this message translates to:
  /// **'Biometric login'**
  String get settingsBiometricLogin;

  /// No description provided for @settingsBiometricLock.
  ///
  /// In en, this message translates to:
  /// **'Biometric lock'**
  String get settingsBiometricLock;

  /// No description provided for @settingsAppLock.
  ///
  /// In en, this message translates to:
  /// **'App lock'**
  String get settingsAppLock;

  /// No description provided for @settingsSecurityAlerts.
  ///
  /// In en, this message translates to:
  /// **'Security alerts'**
  String get settingsSecurityAlerts;

  /// No description provided for @settingsNotifyNewLogin.
  ///
  /// In en, this message translates to:
  /// **'Notify on new login'**
  String get settingsNotifyNewLogin;

  /// No description provided for @settingsNotifyProfileChanges.
  ///
  /// In en, this message translates to:
  /// **'Notify on profile changes'**
  String get settingsNotifyProfileChanges;

  /// No description provided for @settingsCreditNotifications.
  ///
  /// In en, this message translates to:
  /// **'Credit notifications'**
  String get settingsCreditNotifications;

  /// No description provided for @settingsPaymentReminders.
  ///
  /// In en, this message translates to:
  /// **'Payment reminders'**
  String get settingsPaymentReminders;

  /// No description provided for @settingsDueDateAlerts.
  ///
  /// In en, this message translates to:
  /// **'Due date alerts'**
  String get settingsDueDateAlerts;

  /// No description provided for @settingsStatementNotifications.
  ///
  /// In en, this message translates to:
  /// **'Statement notifications'**
  String get settingsStatementNotifications;

  /// No description provided for @settingsChannelSettings.
  ///
  /// In en, this message translates to:
  /// **'Channel settings'**
  String get settingsChannelSettings;

  /// No description provided for @settingsHelpCenter.
  ///
  /// In en, this message translates to:
  /// **'Help center'**
  String get settingsHelpCenter;

  /// No description provided for @settingsDeleteAccountQ.
  ///
  /// In en, this message translates to:
  /// **'Delete account?'**
  String get settingsDeleteAccountQ;

  /// No description provided for @settingsLogoutQ.
  ///
  /// In en, this message translates to:
  /// **'Log out?'**
  String get settingsLogoutQ;

  /// No description provided for @settingsAccountDeleted.
  ///
  /// In en, this message translates to:
  /// **'Account deleted. Signing you out…'**
  String get settingsAccountDeleted;

  /// No description provided for @settingsEmergencyContact.
  ///
  /// In en, this message translates to:
  /// **'Emergency contact'**
  String get settingsEmergencyContact;

  /// No description provided for @settingsEmergencyContactSaved.
  ///
  /// In en, this message translates to:
  /// **'Emergency contact saved.'**
  String get settingsEmergencyContactSaved;

  /// No description provided for @settingsContactMobile.
  ///
  /// In en, this message translates to:
  /// **'Contact mobile number'**
  String get settingsContactMobile;

  /// No description provided for @settingsCompanyInfo.
  ///
  /// In en, this message translates to:
  /// **'Company information'**
  String get settingsCompanyInfo;

  /// No description provided for @settingsMissionStatement.
  ///
  /// In en, this message translates to:
  /// **'Mission statement'**
  String get settingsMissionStatement;

  /// No description provided for @settingsWhatWeOffer.
  ///
  /// In en, this message translates to:
  /// **'What we offer'**
  String get settingsWhatWeOffer;

  /// No description provided for @settingsGetInTouch.
  ///
  /// In en, this message translates to:
  /// **'Get in touch'**
  String get settingsGetInTouch;

  /// No description provided for @settingsOfficeAddress.
  ///
  /// In en, this message translates to:
  /// **'Office address'**
  String get settingsOfficeAddress;

  /// No description provided for @settingsLegalCompliance.
  ///
  /// In en, this message translates to:
  /// **'Legal & compliance'**
  String get settingsLegalCompliance;

  /// No description provided for @settingsLicenses.
  ///
  /// In en, this message translates to:
  /// **'Licenses & accreditations'**
  String get settingsLicenses;

  /// No description provided for @settingsWebsite.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get settingsWebsite;

  /// No description provided for @reviewsTitle.
  ///
  /// In en, this message translates to:
  /// **'Ratings & reviews'**
  String get reviewsTitle;

  /// No description provided for @reviewsWriteReview.
  ///
  /// In en, this message translates to:
  /// **'Write a review'**
  String get reviewsWriteReview;

  /// No description provided for @reviewsSubmitReview.
  ///
  /// In en, this message translates to:
  /// **'Submit review'**
  String get reviewsSubmitReview;

  /// No description provided for @reviewsYourRating.
  ///
  /// In en, this message translates to:
  /// **'Your rating'**
  String get reviewsYourRating;

  /// No description provided for @reviewsPickRating.
  ///
  /// In en, this message translates to:
  /// **'Please pick a star rating'**
  String get reviewsPickRating;

  /// No description provided for @reviewsTitleOptional.
  ///
  /// In en, this message translates to:
  /// **'Title (optional)'**
  String get reviewsTitleOptional;

  /// No description provided for @reviewsSummarise.
  ///
  /// In en, this message translates to:
  /// **'Summarise your experience'**
  String get reviewsSummarise;

  /// No description provided for @reviewsYourReview.
  ///
  /// In en, this message translates to:
  /// **'Your review (optional)'**
  String get reviewsYourReview;

  /// No description provided for @reviewsLikeDislike.
  ///
  /// In en, this message translates to:
  /// **'What did you like or dislike?'**
  String get reviewsLikeDislike;

  /// No description provided for @reviewsThanks.
  ///
  /// In en, this message translates to:
  /// **'Thanks for your review!'**
  String get reviewsThanks;

  /// No description provided for @reviewsSubmitFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not submit review. Please try again.'**
  String get reviewsSubmitFailed;

  /// No description provided for @referralInviteFriends.
  ///
  /// In en, this message translates to:
  /// **'Invite friends'**
  String get referralInviteFriends;

  /// No description provided for @referralInviteFriendsNow.
  ///
  /// In en, this message translates to:
  /// **'Invite friends now'**
  String get referralInviteFriendsNow;

  /// No description provided for @referralHowItWorks.
  ///
  /// In en, this message translates to:
  /// **'How it works'**
  String get referralHowItWorks;

  /// No description provided for @referralHaveCode.
  ///
  /// In en, this message translates to:
  /// **'Have a referral code?'**
  String get referralHaveCode;

  /// No description provided for @referralEnterCode.
  ///
  /// In en, this message translates to:
  /// **'Enter a referral code'**
  String get referralEnterCode;

  /// No description provided for @referralCodeApplied.
  ///
  /// In en, this message translates to:
  /// **'Referral code applied'**
  String get referralCodeApplied;

  /// No description provided for @referralCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied'**
  String get referralCodeCopied;

  /// No description provided for @referralYouEarn.
  ///
  /// In en, this message translates to:
  /// **'You earn'**
  String get referralYouEarn;

  /// No description provided for @referralFirstOrder.
  ///
  /// In en, this message translates to:
  /// **'First order'**
  String get referralFirstOrder;

  /// No description provided for @referralFriendRegisters.
  ///
  /// In en, this message translates to:
  /// **'Friend registers'**
  String get referralFriendRegisters;

  /// No description provided for @referralInviteCopied.
  ///
  /// In en, this message translates to:
  /// **'Invite message copied — paste it to your friends'**
  String get referralInviteCopied;

  /// No description provided for @notifGroupOrders.
  ///
  /// In en, this message translates to:
  /// **'Order notifications'**
  String get notifGroupOrders;

  /// No description provided for @notifGroupPayments.
  ///
  /// In en, this message translates to:
  /// **'Payment notifications'**
  String get notifGroupPayments;

  /// No description provided for @notifGroupCredit.
  ///
  /// In en, this message translates to:
  /// **'Credit notifications'**
  String get notifGroupCredit;

  /// No description provided for @notifGroupPromotional.
  ///
  /// In en, this message translates to:
  /// **'Promotional notifications'**
  String get notifGroupPromotional;

  /// No description provided for @notifOrderConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Order confirmed'**
  String get notifOrderConfirmed;

  /// No description provided for @notifOrderPacked.
  ///
  /// In en, this message translates to:
  /// **'Order packed'**
  String get notifOrderPacked;

  /// No description provided for @notifOrderOutForDelivery.
  ///
  /// In en, this message translates to:
  /// **'Order out for delivery'**
  String get notifOrderOutForDelivery;

  /// No description provided for @notifOrderDelivered.
  ///
  /// In en, this message translates to:
  /// **'Order delivered'**
  String get notifOrderDelivered;

  /// No description provided for @notifPaymentSuccess.
  ///
  /// In en, this message translates to:
  /// **'Payment success'**
  String get notifPaymentSuccess;

  /// No description provided for @notifPaymentFailure.
  ///
  /// In en, this message translates to:
  /// **'Payment failure'**
  String get notifPaymentFailure;

  /// No description provided for @notifCollectionReminders.
  ///
  /// In en, this message translates to:
  /// **'Collection reminders'**
  String get notifCollectionReminders;

  /// No description provided for @notifCreditApproval.
  ///
  /// In en, this message translates to:
  /// **'Credit approval'**
  String get notifCreditApproval;

  /// No description provided for @notifCreditLimitUpdates.
  ///
  /// In en, this message translates to:
  /// **'Credit limit updates'**
  String get notifCreditLimitUpdates;

  /// No description provided for @notifOutstandingDueAlerts.
  ///
  /// In en, this message translates to:
  /// **'Outstanding due alerts'**
  String get notifOutstandingDueAlerts;

  /// No description provided for @notifVsScoreUpdates.
  ///
  /// In en, this message translates to:
  /// **'VS Score updates'**
  String get notifVsScoreUpdates;

  /// No description provided for @notifOffers.
  ///
  /// In en, this message translates to:
  /// **'Offers'**
  String get notifOffers;

  /// No description provided for @notifCoupons.
  ///
  /// In en, this message translates to:
  /// **'Coupons'**
  String get notifCoupons;

  /// No description provided for @notifCashback.
  ///
  /// In en, this message translates to:
  /// **'Cashback'**
  String get notifCashback;

  /// No description provided for @notifReferralRewards.
  ///
  /// In en, this message translates to:
  /// **'Referral rewards'**
  String get notifReferralRewards;

  /// No description provided for @notifPush.
  ///
  /// In en, this message translates to:
  /// **'Push notifications'**
  String get notifPush;

  /// No description provided for @notifSms.
  ///
  /// In en, this message translates to:
  /// **'SMS notifications'**
  String get notifSms;

  /// No description provided for @notifWhatsapp.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp notifications'**
  String get notifWhatsapp;

  /// No description provided for @notifEmail.
  ///
  /// In en, this message translates to:
  /// **'Email notifications'**
  String get notifEmail;

  /// No description provided for @notifLoadError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your notification settings.'**
  String get notifLoadError;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Returns & Refunds'**
  String get returnsTitle;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Requested'**
  String get returnStatusRequested;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get returnStatusApproved;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get returnStatusRejected;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Picked Up'**
  String get returnStatusPicked;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Refunded'**
  String get returnStatusRefunded;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'No returns yet'**
  String get returnsEmptyTitle;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Returns and refunds you request will appear here.'**
  String get returnsEmptyBody;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Order {code}'**
  String returnsOrderNumber(String code);

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get returnsReasonLabel;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Refund'**
  String get returnsRefundLabel;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Return / Refund'**
  String get returnRequestTitle;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get returnRequestOrderLabel;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Reason for Return'**
  String get returnRequestReasonLabel;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Select a reason'**
  String get returnRequestSelectReason;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Description (Optional)'**
  String get returnRequestDescriptionLabel;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Tell us more about the issue...'**
  String get returnRequestDescriptionHint;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Submit Request'**
  String get returnRequestSubmit;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Could not request a return. Please try again.'**
  String get returnRequestError;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Photos of the item'**
  String get returnRequestPhotosLabel;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Add clear photos showing the item and the issue. Our pickup partner will check these at your door.'**
  String get returnRequestPhotosHint;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Add photo'**
  String get returnRequestAddPhoto;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Add at least one photo of the item.'**
  String get returnRequestPhotoRequired;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'You can add up to {count} photos.'**
  String returnRequestPhotoLimit(int count);

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Remove photo'**
  String get returnRequestRemovePhoto;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Damaged item'**
  String get returnReasonDamaged;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Wrong item'**
  String get returnReasonWrong;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Quality issue'**
  String get returnReasonQuality;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Changed my mind'**
  String get returnReasonChangedMind;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get returnReasonOther;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Fresh Groceries, Delivered Fast!'**
  String get onboardingSlide1Caption;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Fresh Groceries Delivered To Your Doorstep'**
  String get onboardingSlide1Title;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Order vegetables, fruits, dairy products, household essentials, and daily groceries with fast delivery.'**
  String get onboardingSlide1Body;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Shop Now, Pay Later'**
  String get onboardingSlide2Caption;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Shop With VS Credit, Pay On Your Terms'**
  String get onboardingSlide2Title;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Buy what you need today and settle later with flexible weekly or monthly credit — no hidden charges.'**
  String get onboardingSlide2Body;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Grow Your VS Score'**
  String get onboardingSlide3Caption;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Build Your Credit Score As You Shop'**
  String get onboardingSlide3Title;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Every on-time payment strengthens your VS Score and unlocks higher credit limits and better offers.'**
  String get onboardingSlide3Body;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get onboardingGetStarted;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Update Required'**
  String get systemUpdateTitle;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'A newer version of VS Mart is available with important improvements. Please update from the Play Store to continue.'**
  String get systemUpdateBody;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Update Now'**
  String get systemUpdateNow;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'I\'ve updated — Check again'**
  String get systemUpdatedCheckAgain;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Could not open the Play Store. Please search for \"VS Mart\" to update.'**
  String get systemPlayStoreError;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Under Maintenance'**
  String get systemMaintenanceTitle;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'We\'re sprucing things up and will be back shortly. Thanks for your patience.'**
  String get systemMaintenanceBody;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get systemTryAgain;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'No Internet Connection'**
  String get systemNoInternetTitle;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get systemNoInternetBody;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Confirm Payment'**
  String get collectionConfirmTitle;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the confirmation.'**
  String get collectionConfirmLoadError;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Nothing to confirm'**
  String get collectionConfirmNothingTitle;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'You have no pending cash collection right now.'**
  String get collectionConfirmNothingBody;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'{name} is collecting'**
  String collectionConfirmCollecting(String name);

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'SHARE THIS CODE'**
  String get collectionConfirmShareCode;

  /// MT: needs native review. {amount} is a pre-formatted currency string like ₹250.00.
  ///
  /// In en, this message translates to:
  /// **'Only share this code if you are paying {amount} in cash. Never share it otherwise.'**
  String collectionConfirmSafetyWarning(String amount);

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Payment confirmed'**
  String get collectionConfirmDoneTitle;

  /// MT: needs native review. {amount} is a pre-formatted currency string like ₹250.00.
  ///
  /// In en, this message translates to:
  /// **'{name} has received {amount} in cash.'**
  String collectionConfirmDoneBody(String name, String amount);

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Set your location'**
  String get locationPickerTitle;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Confirm location'**
  String get locationConfirm;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Drag the map or tap to place the pin'**
  String get locationDragHint;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t get your location.'**
  String get locationCouldNotGet;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Location permission needed.'**
  String get locationPermissionNeeded;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Find your area, then drop the pin on your exact spot.'**
  String get locationSearchSubtitle;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Search area, street or landmark'**
  String get locationSearchHint;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load that place. Try another.'**
  String get locationPlaceLoadError;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Search isn\'t available right now. Use your current location, or check your connection and retry.'**
  String get locationSearchUnavailable;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'No matches. Try a different search.'**
  String get locationNoMatches;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Payment Reminders'**
  String get paymentReminderTitle;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your reminder preferences.'**
  String get paymentReminderLoadError;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Reminder preferences saved.'**
  String get paymentReminderSaved;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Could not save preferences.'**
  String get paymentReminderSaveError;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Stay on track'**
  String get paymentReminderHeadline;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Configure your alerts to avoid late fees and maintain a healthy credit score with VS Mart.'**
  String get paymentReminderSubtitle;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Enable Reminders'**
  String get paymentReminderEnableTitle;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Get notified before your due date'**
  String get paymentReminderEnableSubtitle;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'When should we remind you?'**
  String get paymentReminderWhenTitle;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'3 Days Before'**
  String get paymentReminderThreeDays;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Best for planning ahead'**
  String get paymentReminderThreeDaysSub;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'1 Day Before'**
  String get paymentReminderOneDay;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Quick reminder'**
  String get paymentReminderOneDaySub;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'On Due Date'**
  String get paymentReminderOnDueDate;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Morning of payment'**
  String get paymentReminderOnDueDateSub;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'A Week Before'**
  String get paymentReminderWeekBefore;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Maximum lead time'**
  String get paymentReminderWeekBeforeSub;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'How should we reach you?'**
  String get paymentReminderHowTitle;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'WhatsApp'**
  String get paymentReminderWhatsApp;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Instant message delivery'**
  String get paymentReminderWhatsAppSub;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Push Notification'**
  String get paymentReminderPush;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Direct to your VS Mart app'**
  String get paymentReminderPushSub;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'SMS Text'**
  String get paymentReminderSms;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Standard text message'**
  String get paymentReminderSmsSub;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Preferred Time'**
  String get paymentReminderPreferredTime;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Time of day'**
  String get paymentReminderTimeOfDay;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Setting reminders helps you avoid late fees and positively impacts your credit health by ensuring timely payments.'**
  String get paymentReminderInfoBanner;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Save Preferences'**
  String get paymentReminderSave;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Frequently Asked Questions'**
  String get supportFaqsHeadline;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load FAQs.'**
  String get supportFaqsLoadError;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'No FAQs match your search.'**
  String get supportNoFaqsMatch;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Our support team is here to assist you.'**
  String get supportTeamHereToAssist;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Contact Support'**
  String get supportContactSupport;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'You can attach up to 3 files.'**
  String get supportAttachLimit;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Ticket submitted'**
  String get supportTicketSubmitted;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Tap to upload photos'**
  String get supportTapToUploadPhotos;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Max 3 files, 5MB each'**
  String get supportMaxFilesSize;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Our team typically responds within 24 hours.'**
  String get supportRespondsWithin24h;

  /// MT: needs native review. VS-TKT- is a fixed ticket-code prefix; do not translate.
  ///
  /// In en, this message translates to:
  /// **'Ticket VS-TKT-{id}'**
  String supportTicketCode(String id);

  /// MT: needs native review. VS-TKT- is a fixed ticket-code prefix; do not translate.
  ///
  /// In en, this message translates to:
  /// **'Ticket VS-TKT-{id} opened'**
  String supportTicketOpened(String id);

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Search for help, orders, payments, credit issues…'**
  String get supportSearchPrompt;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Ticket not found.'**
  String get supportTicketNotFound;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Close this ticket?'**
  String get supportCloseTicketQ;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'This tells our team the issue is resolved and stops further work on it. You can always raise a new ticket later.'**
  String get supportCloseTicketBody;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Ticket closed.'**
  String get supportTicketClosed;

  /// MT: needs native review. {target} is a localized phrase like 'the dialer' or 'your email app'.
  ///
  /// In en, this message translates to:
  /// **'Could not open {target}.'**
  String settingsCouldNotOpen(String target);

  /// MT: needs native review. Fills the {target} slot in settingsCouldNotOpen.
  ///
  /// In en, this message translates to:
  /// **'the dialer'**
  String get settingsOpenTargetDialer;

  /// MT: needs native review. Fills the {target} slot in settingsCouldNotOpen.
  ///
  /// In en, this message translates to:
  /// **'your email app'**
  String get settingsOpenTargetEmail;

  /// MT: needs native review. Fills the {target} slot in settingsCouldNotOpen.
  ///
  /// In en, this message translates to:
  /// **'the link'**
  String get settingsOpenTargetLink;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'VS Mart is a pioneering hybrid ecosystem bridging the gap between daily grocery commerce and flexible financial credit, ensuring families have seamless access to essentials when they need them most.'**
  String get settingsCompanyDescription;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'\"To empower communities by providing fresh, affordable groceries coupled with trustworthy, flexible credit solutions, creating a stress-free shopping experience.\"'**
  String get settingsMissionText;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Grocery Shopping'**
  String get settingsOfferGroceryTitle;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Fresh daily essentials'**
  String get settingsOfferGrocerySubtitle;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Flexible payment options'**
  String get settingsOfferCreditSubtitle;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Delivery Services'**
  String get settingsOfferDeliveryTitle;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Fast & reliable delivery'**
  String get settingsOfferDeliverySubtitle;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Digital Collections'**
  String get settingsOfferCollectionsTitle;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Seamless repayment'**
  String get settingsOfferCollectionsSubtitle;

  /// MT: needs native review. {app} is the app name (VS Mart).
  ///
  /// In en, this message translates to:
  /// **'© 2026 {app}. All rights reserved.'**
  String settingsAllRightsReserved(String app);

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Require fingerprint / Face ID to open VS Mart'**
  String get settingsBiometricLockSubtitle;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Get notified when your account signs in'**
  String get settingsNotifyNewLoginSubtitle;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Alert me when account details change'**
  String get settingsNotifyProfileChangesSubtitle;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Your VS Mart account is secured with one-time password (OTP) login on every sign-in.'**
  String get settingsOtpSecurityNote;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'We could not find your account contact. Please sign in again.'**
  String get settingsNoAccountContact;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Deletion requested — we\'ll process it and remove your account.'**
  String get settingsDeletionRequested;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Credit'**
  String get billingCreditTab;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'We\'re verifying your details. Your VS Credit line will unlock here once approved — usually within a few hours.'**
  String get billingCreditPendingBody;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'View Status'**
  String get billingViewStatus;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Your last credit application wasn\'t approved. You can review your details and apply again.'**
  String get billingCreditRejectedBody;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Unlock VS Credit'**
  String get billingUnlockCredit;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Shop now and pay later with a VS Credit line. Complete a quick KYC verification to apply — it only takes a few minutes.'**
  String get billingCreditApplyBody;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Apply for Credit'**
  String get billingApplyForCredit;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Your information is encrypted and used only for credit verification.'**
  String get billingCreditEncryptedNote;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Shop Now, Pay Later'**
  String get billingBenefitShopPayLater;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Flexible Weekly / Monthly Plans'**
  String get billingBenefitFlexiblePlans;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Exclusive Member Offers'**
  String get billingBenefitMemberOffers;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Build Your VS Score'**
  String get billingBenefitBuildScore;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Why VS Credit?'**
  String get billingWhyVsCredit;

  /// MT: needs native review. Credit utilization badge.
  ///
  /// In en, this message translates to:
  /// **'{percent}% used'**
  String billingPercentUsed(int percent);

  /// MT: needs native review. {amount} is a pre-formatted currency string like ₹25,000.
  ///
  /// In en, this message translates to:
  /// **'Used: {amount}'**
  String billingUsedAmount(String amount);

  /// MT: needs native review. {amount} is a pre-formatted currency string like ₹50,000.
  ///
  /// In en, this message translates to:
  /// **'Total Limit: {amount}'**
  String billingTotalLimitAmount(String amount);

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Collection request raised. An agent will be assigned to visit you.'**
  String get billingCollectionRequestRaised;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Collection Address'**
  String get billingCollectionAddress;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Registered address'**
  String get billingRegisteredAddress;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'The agent will visit your saved delivery address'**
  String get billingAgentVisitAddress;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Any instructions for the collection agent (optional)'**
  String get billingCollectionNotesHint;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'A VS Mart collection agent will be assigned and visit your location to collect the payment securely. You will be notified once an agent is confirmed.'**
  String get billingCollectionAgentInfo;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Amount to Collect'**
  String get billingAmountToCollect;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount'**
  String get billingEnterValidAmount;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Request'**
  String get billingRequest;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Cash collection pickups you request will appear here.'**
  String get billingCollectionsAppearHere;

  /// MT: needs native review. {date} is a formatted date like 5 Jul 2026.
  ///
  /// In en, this message translates to:
  /// **'Requested {date}'**
  String billingRequestedOn(String date);

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get billingAddress;

  /// MT: needs native review. {order} is an order id, {date} a formatted date.
  ///
  /// In en, this message translates to:
  /// **'Order {order} • {date}'**
  String billingOrderDate(String order, String date);

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Could not load the invoice'**
  String get billingInvoiceLoadError;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Outstanding Due'**
  String get billingOutstandingDue;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your dues.'**
  String get billingDuesLoadError;

  /// MT: needs native review. {date} is a formatted date like 5 July 2026.
  ///
  /// In en, this message translates to:
  /// **'Due: {date}'**
  String billingDueOnDate(String date);

  /// MT: needs native review. Number of days a payment is overdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue by {days} Days'**
  String billingOverdueByDays(int days);

  /// MT: needs native review. Number of days until a payment is due.
  ///
  /// In en, this message translates to:
  /// **'Due in {days} Days'**
  String billingDueInDays(int days);

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Total Outstanding Amount'**
  String get billingTotalOutstandingAmount;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Pay before the due date to maintain a healthy VS Score and avoid late fees.'**
  String get billingPayBeforeDueNote;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Paying Total Amount'**
  String get billingPayingTotalAmount;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Receipt downloaded'**
  String get billingReceiptDownloaded;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Collection requested. An agent will be assigned.'**
  String get billingCollectionRequested;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Could not raise the request. Try again.'**
  String get billingCollectionRequestError;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Payment failed. Please try again.'**
  String get billingPaymentFailed;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Proceed to Pay'**
  String get billingProceedToPay;

  /// MT: needs native review. Displayed uppercased in the UI.
  ///
  /// In en, this message translates to:
  /// **'Outstanding amount'**
  String get billingOutstandingAmount;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Debit / Credit card'**
  String get billingDebitCreditCard;

  /// MT: needs native review. NEFT and IMPS are bank-transfer scheme names, keep as-is.
  ///
  /// In en, this message translates to:
  /// **'NEFT / IMPS transfer'**
  String get billingNeftImpsTransfer;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Request an agent pickup'**
  String get billingRequestAgentPickup;

  /// MT: needs native review. Displayed uppercased in the UI.
  ///
  /// In en, this message translates to:
  /// **'Credit updated'**
  String get billingCreditUpdated;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Statement downloaded'**
  String get billingStatementDownloaded;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'No transactions in this cycle.'**
  String get billingNoTransactionsInCycle;

  /// MT: needs native review. {amount} is a pre-formatted currency string like ₹1,200.
  ///
  /// In en, this message translates to:
  /// **'Pay {amount}'**
  String billingPayAmount(String amount);

  /// MT: needs native review. Statement status chip.
  ///
  /// In en, this message translates to:
  /// **'Due'**
  String get billingStatusDue;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Generated'**
  String get billingGenerated;

  /// MT: needs native review. Running credit balance after a ledger entry. {amount} is a pre-formatted currency string.
  ///
  /// In en, this message translates to:
  /// **'Bal {amount}'**
  String billingBalanceAmount(String amount);

  /// MT: needs native review. {date} is a formatted date like 5 Jul.
  ///
  /// In en, this message translates to:
  /// **'Payment due {date}'**
  String billingPaymentDue(String date);

  /// MT: needs native review. {amount} and {min} are pre-formatted currency strings.
  ///
  /// In en, this message translates to:
  /// **'{amount} due • min {min}'**
  String billingAmountDueMin(String amount, String min);

  /// MT: needs native review. {amount} is a pre-formatted currency string.
  ///
  /// In en, this message translates to:
  /// **'{amount} due'**
  String billingAmountDueShort(String amount);

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Pay'**
  String get billingPay;

  /// MT: needs native review. Date-picker header.
  ///
  /// In en, this message translates to:
  /// **'Date of birth (as per PAN)'**
  String get kycDobHelpText;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Apply for VS Credit'**
  String get kycApplyVsCredit;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Step 1 of 2 · Verify your details'**
  String get kycStep1VerifyDetails;

  /// MT: needs native review. CIBIL is a credit-bureau brand name, keep as-is.
  ///
  /// In en, this message translates to:
  /// **'Enter your details as on your PAN. We\'ll fetch your CIBIL score on your registered number to verify your identity.'**
  String get kycDetailsIntro;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Name as per PAN'**
  String get kycNameAsPerPan;

  /// MT: needs native review. Example name hint; may be localised to a locale-appropriate sample name.
  ///
  /// In en, this message translates to:
  /// **'e.g. Srinivasu Magapu'**
  String get kycFullNameHint;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Select your date of birth'**
  String get kycSelectDob;

  /// MT: needs native review. CIBIL is a credit-bureau brand name, keep as-is.
  ///
  /// In en, this message translates to:
  /// **'Check CIBIL'**
  String get kycCheckCibil;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Identity verified'**
  String get kycIdentityVerified;

  /// MT: needs native review. CIBIL is a brand name; {score} is the numeric credit score.
  ///
  /// In en, this message translates to:
  /// **'CIBIL {score}'**
  String kycCibilScore(String score);

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Step 2 of 2 · Upload documents'**
  String get kycStep2Documents;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Clear photos of both sides of your Aadhaar and PAN cards. An agent will verify them.'**
  String get kycDocsIntro;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Aadhaar — front'**
  String get kycAadhaarFront;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Aadhaar — back'**
  String get kycAadhaarBack;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'PAN — front'**
  String get kycPanFront;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'PAN — back'**
  String get kycPanBack;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Submit for verification'**
  String get kycSubmitForVerification;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Application submitted'**
  String get kycApplicationSubmitted;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'An agent will be assigned to verify your documents. Your VS Credit limit unlocks once they approve.'**
  String get kycApplicationSubmittedBody;

  /// MT: needs native review. CIBIL is a brand name, keep as-is.
  ///
  /// In en, this message translates to:
  /// **'Your CIBIL Score'**
  String get kycYourCibilScore;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Tap to change'**
  String get kycTapToChange;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Tap to upload'**
  String get kycTapToUpload;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'I authorise VS Mart to fetch my credit score from the bureau to verify my identity and assess my credit eligibility.'**
  String get kycConsentText;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Live Selfie'**
  String get kycLiveSelfie;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Mobile Verified'**
  String get kycMobileVerified;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Address Added'**
  String get kycAddressAdded;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your verification status.'**
  String get kycStatusLoadError;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Re-submit Documents'**
  String get kycResubmitDocuments;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Complete verification to unlock VS Credit benefits.'**
  String get kycCompleteToUnlock;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Instant verification'**
  String get kycInstantVerification;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Verify with your PAN & credit score in a minute'**
  String get kycInstantVerifyBody;

  /// MT: needs native review. Progress caption on the KYC dashboard.
  ///
  /// In en, this message translates to:
  /// **'{completed} of {total} Steps Completed'**
  String kycStepsCompleted(int completed, int total);

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'On approval'**
  String get kycBenefitOnApproval;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Flexible Plans'**
  String get kycBenefitFlexiblePlans;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Weekly / Monthly'**
  String get kycBenefitWeeklyMonthly;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Exclusive Offers'**
  String get kycBenefitExclusiveOffers;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Member Only'**
  String get kycBenefitMemberOnly;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Build Credit'**
  String get kycBenefitBuildCredit;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Unlock VS Credit Benefits'**
  String get kycUnlockBenefits;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Your information is encrypted and securely stored following bank-grade security standards.'**
  String get kycSecurityNote;

  /// MT: needs native review. RBI is the Reserve Bank of India, keep as-is.
  ///
  /// In en, this message translates to:
  /// **'KYC verification is required to unlock your full credit limit and ensure compliance with RBI regulations. We use bank-grade encryption.'**
  String get kycSecurityBannerBody;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'All required documents have been successfully verified.'**
  String get kycCaptionVerified;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Your documents are under review. This usually takes 1–2 days.'**
  String get kycCaptionPending;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Some documents could not be verified. Please re-submit.'**
  String get kycCaptionRejected;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Complete your KYC to unlock your full credit limit.'**
  String get kycCaptionNotStarted;

  /// MT: needs native review. KYC completion percentage chip.
  ///
  /// In en, this message translates to:
  /// **'{percent}% Complete'**
  String kycPercentComplete(int percent);

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Submit your Aadhaar, PAN and a selfie to verify your identity.'**
  String get kycStartCardBody;

  /// MT: needs native review. Document submitted state.
  ///
  /// In en, this message translates to:
  /// **'Submitted'**
  String get kycSubmitted;

  /// MT: needs native review. Divider label between two alternatives.
  ///
  /// In en, this message translates to:
  /// **'OR'**
  String get commonOr;

  /// MT: needs native review. Discount badge, e.g. 20% OFF.
  ///
  /// In en, this message translates to:
  /// **'{percent}% OFF'**
  String discountPercentOff(int percent);

  /// MT: needs native review. Loader while GPS serviceability check resolves.
  ///
  /// In en, this message translates to:
  /// **'Checking your area…'**
  String get serviceCheckingArea;

  /// MT: needs native review.
  ///
  /// In en, this message translates to:
  /// **'Confirming we deliver where you are.'**
  String get serviceConfirmingDelivery;

  /// MT: needs native review. Shown when the device location couldn't be confirmed.
  ///
  /// In en, this message translates to:
  /// **'Set your location to continue'**
  String get serviceSetLocationTitle;

  /// MT: needs native review. Out-of-coverage headline.
  ///
  /// In en, this message translates to:
  /// **'VS Mart isn\'t in your area yet'**
  String get serviceNotInAreaTitle;

  /// MT: needs native review.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t confirm your location. Set it so we can check if VS Mart delivers near you.'**
  String get serviceCouldntConfirmBody;

  /// MT: needs native review.
  ///
  /// In en, this message translates to:
  /// **'We\'re expanding fast. Change your location to shop from a serviceable area near you.'**
  String get serviceExpandingBody;

  /// MT: needs native review. CTA to register interest for an out-of-area location.
  ///
  /// In en, this message translates to:
  /// **'Notify me when you\'re here'**
  String get serviceNotifyWhenHere;

  /// MT: needs native review.
  ///
  /// In en, this message translates to:
  /// **'Location is turned off on your phone. Turn it on, then try again.'**
  String get serviceLocationOffNote;

  /// MT: needs native review.
  ///
  /// In en, this message translates to:
  /// **'Open location settings'**
  String get serviceOpenLocationSettings;

  /// MT: needs native review.
  ///
  /// In en, this message translates to:
  /// **'Location permission is blocked for VS Mart. Enable it in Settings, then try again.'**
  String get serviceLocationBlockedNote;

  /// MT: needs native review.
  ///
  /// In en, this message translates to:
  /// **'Open app settings'**
  String get serviceOpenAppSettings;

  /// MT: needs native review.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t get a GPS fix. Move near a window or step outside and try again, or search for your area instead.'**
  String get serviceNoGpsFixNote;

  /// MT: needs native review.
  ///
  /// In en, this message translates to:
  /// **'We don\'t deliver there yet. Try a different location.'**
  String get serviceDontDeliverThereNote;

  /// MT: needs native review.
  ///
  /// In en, this message translates to:
  /// **'Use your current location, or search your area and drop the pin.'**
  String get serviceChangeLocationBody;

  /// MT: needs native review.
  ///
  /// In en, this message translates to:
  /// **'Use my current location'**
  String get serviceUseMyCurrentLocation;

  /// MT: needs native review.
  ///
  /// In en, this message translates to:
  /// **'Search area & drop pin'**
  String get serviceSearchAreaDropPin;

  /// MT: needs native review.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get serviceOpenSettings;

  /// MT: needs native review.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid phone number'**
  String get serviceEnterValidPhone;

  /// MT: needs native review.
  ///
  /// In en, this message translates to:
  /// **'Leave your number and we\'ll message you the moment VS Mart starts delivering in your area.'**
  String get serviceNotifyBody;

  /// MT: needs native review. Optional name field label.
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get serviceNameOptional;

  /// MT: needs native review. Phone input hint.
  ///
  /// In en, this message translates to:
  /// **'e.g. +9198XXXXXXXX'**
  String get servicePhoneHintExample;

  /// MT: needs native review. Success title after registering interest.
  ///
  /// In en, this message translates to:
  /// **'We\'ll notify you'**
  String get serviceWellNotifyYou;

  /// MT: needs native review.
  ///
  /// In en, this message translates to:
  /// **'Thanks! We\'ve registered your interest and will message you as soon as we start delivering near you.'**
  String get serviceNotifySuccessBody;

  /// MT: needs native review. Empty-wishlist CTA.
  ///
  /// In en, this message translates to:
  /// **'Browse Products'**
  String get wishlistBrowseProducts;

  /// MT: needs native review. Wishlist filter tab.
  ///
  /// In en, this message translates to:
  /// **'Price Drop'**
  String get wishlistPriceDrop;

  /// MT: needs native review. Snackbar after removing a product from wishlist.
  ///
  /// In en, this message translates to:
  /// **'{name} removed from wishlist'**
  String wishlistRemoved(String name);

  /// MT: needs native review. Quick price filter chip.
  ///
  /// In en, this message translates to:
  /// **'Under ₹99'**
  String get searchUnderPrice;

  /// MT: needs native review. Result count header.
  ///
  /// In en, this message translates to:
  /// **'{count} Results found'**
  String searchResultsFound(int count);

  /// MT: needs native review. Empty search results message.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find anything for \"{query}\".'**
  String searchNoResultsFor(String query);

  /// MT: needs native review. Prefix before the selected sort option.
  ///
  /// In en, this message translates to:
  /// **'Sort: '**
  String get searchSortPrefix;

  /// MT: needs native review. Active-filters pill.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Filter Applied} other{{count} Filters Applied}}'**
  String searchFiltersApplied(int count);

  /// MT: needs native review. Prefix before the typed query in the autocomplete row.
  ///
  /// In en, this message translates to:
  /// **'Search for '**
  String get searchForPrefix;

  /// MT: needs native review. Validation error when a review body exceeds the max length.
  ///
  /// In en, this message translates to:
  /// **'Your review is too long (max {max} characters).'**
  String reviewsTooLong(int max);

  /// MT: needs native review. Accessibility value for a star rating row.
  ///
  /// In en, this message translates to:
  /// **'{rating} out of 5 stars'**
  String reviewsRatingValue(int rating);

  /// MT: needs native review. Review count under the rating summary.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 review} other{{count} reviews}}'**
  String reviewsCount(int count);

  /// MT: needs native review. Empty reviews state.
  ///
  /// In en, this message translates to:
  /// **'No reviews yet — be the first'**
  String get reviewsNoneYet;

  /// MT: needs native review. Accessibility tooltip on a selectable star.
  ///
  /// In en, this message translates to:
  /// **'{star, plural, =1{Rate 1 star} other{Rate {star} stars}}'**
  String reviewsRateStars(int star);

  /// MT: needs native review. Referral code input hint.
  ///
  /// In en, this message translates to:
  /// **'e.g. VS00042'**
  String get referralCodeHint;

  /// MT: needs native review.
  ///
  /// In en, this message translates to:
  /// **'Terms & Conditions Apply'**
  String get referralTermsApply;

  /// MT: needs native review. {amount} is a pre-formatted currency string like ₹50.
  ///
  /// In en, this message translates to:
  /// **'Earn {amount} Per Successful Referral'**
  String referralEarnPerReferral(String amount);

  /// MT: needs native review.
  ///
  /// In en, this message translates to:
  /// **'No referrals yet — invite to start earning'**
  String get referralNoneYet;

  /// MT: needs native review. Count of completed referrals.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 successful referral} other{{count} successful referrals}}'**
  String referralSuccessfulCount(int count);

  /// MT: needs native review. Label above the referral code.
  ///
  /// In en, this message translates to:
  /// **'Your Referral Code'**
  String get referralYourCode;

  /// MT: needs native review. How-it-works step body.
  ///
  /// In en, this message translates to:
  /// **'Share your unique link or code.'**
  String get referralStepShareBody;

  /// MT: needs native review. How-it-works step body.
  ///
  /// In en, this message translates to:
  /// **'They sign up using your code.'**
  String get referralStepRegisterBody;

  /// MT: needs native review. How-it-works step body.
  ///
  /// In en, this message translates to:
  /// **'They place their first valid order.'**
  String get referralStepOrderBody;

  /// MT: needs native review. {amount} is a pre-formatted currency string like ₹50.
  ///
  /// In en, this message translates to:
  /// **'Get {amount} added to your wallet.'**
  String referralStepEarnBody(String amount);

  /// MT: needs native review. Error row when deals fail to load.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load deals.'**
  String get offersCouldntLoadDeals;

  /// MT: needs native review. Error row when coupons fail to load.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load coupons.'**
  String get offersCouldntLoadCoupons;

  /// MT: needs native review. Promo hero headline.
  ///
  /// In en, this message translates to:
  /// **'Up to 60% OFF'**
  String get offersUpTo60Off;

  /// MT: needs native review. Promo hero subtitle.
  ///
  /// In en, this message translates to:
  /// **'On groceries & daily essentials'**
  String get offersOnGroceries;

  /// MT: needs native review. Screen title / section heading.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Deals'**
  String get offersTodaysDeals;

  /// MT: needs native review. Flash-sale banner headline.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Mega Savings'**
  String get offersMegaSavings;

  /// MT: needs native review. Flash-sale banner subtitle.
  ///
  /// In en, this message translates to:
  /// **'Up to 60% off on fresh produce & essentials'**
  String get offersUpTo60OffProduce;

  /// MT: needs native review. Deals filter chip.
  ///
  /// In en, this message translates to:
  /// **'Flash Sale'**
  String get offersFilterFlashSale;

  /// MT: needs native review. Deals filter chip.
  ///
  /// In en, this message translates to:
  /// **'Top Discounts'**
  String get offersFilterTopDiscounts;

  /// MT: needs native review. Deals filter chip.
  ///
  /// In en, this message translates to:
  /// **'Buy 1 Get 1'**
  String get offersFilterBuy1Get1;

  /// MT: needs native review. Low-stock urgency label on a featured deal.
  ///
  /// In en, this message translates to:
  /// **'Only 5 left!'**
  String get offersOnlyFiveLeft;

  /// MT: needs native review. Stock-claimed progress label on a featured deal.
  ///
  /// In en, this message translates to:
  /// **'80% Claimed'**
  String get offersClaimedPercent;

  /// MT: needs native review. Coupon code chip on a banner. {code} is the coupon code.
  ///
  /// In en, this message translates to:
  /// **'Code: {code}'**
  String offersCodeLabel(String code);

  /// MT: needs native review. CTA / dialog title to redeem reward points.
  ///
  /// In en, this message translates to:
  /// **'Redeem Points'**
  String get loyaltyRedeemPoints;

  /// MT: needs native review. Hero card label.
  ///
  /// In en, this message translates to:
  /// **'Reward Points'**
  String get loyaltyRewardPoints;

  /// MT: needs native review. Caption under the points balance.
  ///
  /// In en, this message translates to:
  /// **'points available'**
  String get loyaltyPointsAvailable;

  /// MT: needs native review. {points} is a pre-formatted number string.
  ///
  /// In en, this message translates to:
  /// **'Lifetime earned: {points} pts'**
  String loyaltyLifetimeEarned(String points);

  /// MT: needs native review. Empty ledger title.
  ///
  /// In en, this message translates to:
  /// **'No points activity yet'**
  String get loyaltyNoActivity;

  /// MT: needs native review. Empty ledger body.
  ///
  /// In en, this message translates to:
  /// **'Earn and redeem points to see your history here.'**
  String get loyaltyNoActivityBody;

  /// MT: needs native review. Ledger row fallback label.
  ///
  /// In en, this message translates to:
  /// **'Points earned'**
  String get loyaltyPointsEarned;

  /// MT: needs native review. Ledger row fallback label.
  ///
  /// In en, this message translates to:
  /// **'Points redeemed'**
  String get loyaltyPointsRedeemed;

  /// MT: needs native review. Ledger row fallback label.
  ///
  /// In en, this message translates to:
  /// **'Points expired'**
  String get loyaltyPointsExpired;

  /// MT: needs native review. Ledger row fallback label.
  ///
  /// In en, this message translates to:
  /// **'Points adjustment'**
  String get loyaltyPointsAdjustment;

  /// MT: needs native review. Redeem validation error.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid number of points'**
  String get loyaltyEnterValidPoints;

  /// MT: needs native review. Redeem validation error. {points} is a pre-formatted number string.
  ///
  /// In en, this message translates to:
  /// **'You only have {points} points'**
  String loyaltyOnlyHavePoints(String points);

  /// MT: needs native review. Redeem dialog body. {points} is a pre-formatted number string.
  ///
  /// In en, this message translates to:
  /// **'You have {points} points available.'**
  String loyaltyPointsAvailableSentence(String points);

  /// MT: needs native review. Redeem input label.
  ///
  /// In en, this message translates to:
  /// **'Points to redeem'**
  String get loyaltyPointsToRedeem;

  /// MT: needs native review. Redeem input hint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 100'**
  String get loyaltyPointsHint;

  /// MT: needs native review. Redeem confirm button.
  ///
  /// In en, this message translates to:
  /// **'Redeem'**
  String get loyaltyRedeem;

  /// MT: needs native review. Empty notifications message.
  ///
  /// In en, this message translates to:
  /// **'You\'re all caught up.'**
  String get notificationsAllCaughtUp;

  /// MT: needs native review. Notifications group heading.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get notificationsYesterday;

  /// MT: needs native review. Active-order tracker card. {id} is the order id.
  ///
  /// In en, this message translates to:
  /// **'Order #{id}'**
  String homeOrderNumber(String id);

  /// MT: needs native review. Inline section load-error label.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load'**
  String get homeCouldntLoad;

  /// MT: needs native review. Snackbar when order placement is blocked locally.
  ///
  /// In en, this message translates to:
  /// **'Could not place order. Please review your cart.'**
  String get checkoutCouldNotPlaceOrder;

  /// MT: needs native review. Line-item quantity in the order summary.
  ///
  /// In en, this message translates to:
  /// **'Qty {count}'**
  String checkoutQty(int count);

  /// MT: needs native review. Applied-coupon confirmation. {code} is the coupon code, {amount} a pre-formatted currency string.
  ///
  /// In en, this message translates to:
  /// **'“{code}” applied — {amount} off'**
  String checkoutCouponAppliedOff(String code, String amount);

  /// MT: needs native review. Repayment plan payout date. {date} is a pre-formatted date string.
  ///
  /// In en, this message translates to:
  /// **'Due {date}'**
  String checkoutDueDate(String date);

  /// MT: needs native review. Snackbar when payment setup fails.
  ///
  /// In en, this message translates to:
  /// **'Could not complete payment. Check your cart and address.'**
  String get paymentCouldNotComplete;

  /// MT: needs native review. Snackbar when an online payment is not completed.
  ///
  /// In en, this message translates to:
  /// **'Payment not completed. Your order is saved — you can retry from My Orders.'**
  String get paymentNotCompleted;

  /// MT: needs native review. Out-of-stock sheet title.
  ///
  /// In en, this message translates to:
  /// **'Some items are unavailable'**
  String get cartItemsUnavailableTitle;

  /// MT: needs native review. Out-of-stock sheet body.
  ///
  /// In en, this message translates to:
  /// **'These went out of stock at your store. Remove them to continue.'**
  String get cartItemsUnavailableBody;

  /// MT: needs native review. Removes unavailable items and proceeds to checkout.
  ///
  /// In en, this message translates to:
  /// **'Remove & continue'**
  String get cartRemoveAndContinue;

  /// MT: needs native review. Dismisses the out-of-stock sheet to review the cart.
  ///
  /// In en, this message translates to:
  /// **'Review cart'**
  String get cartReviewCart;

  /// MT: needs native review. Sign-in-to-checkout prompt body.
  ///
  /// In en, this message translates to:
  /// **'Create an account or sign in to place your order and pay. Your cart will be waiting for you.'**
  String get cartSignInBody;

  /// MT: needs native review. Shown when the server bill total can't be fetched.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t fetch the latest total — showing an estimate. Tap to retry.'**
  String get cartTotalEstimateError;

  /// MT: needs native review. Order id header/label.
  ///
  /// In en, this message translates to:
  /// **'Order #{id}'**
  String ordersOrderNumber(Object id);

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Cancel order?'**
  String get ordersCancelConfirmTitle;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Cancel this order? This can\'t be undone.'**
  String get ordersCancelConfirmBody;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Keep order'**
  String get ordersKeepOrder;

  /// MT: needs native review. Snackbar after cancelling an order.
  ///
  /// In en, this message translates to:
  /// **'Order cancelled'**
  String get ordersCancelled;

  /// MT: needs native review. Card title for order progress timeline.
  ///
  /// In en, this message translates to:
  /// **'Order Timeline'**
  String get ordersTimeline;

  /// MT: needs native review. Order line item name with quantity. name is product data.
  ///
  /// In en, this message translates to:
  /// **'{name}  ×{quantity}'**
  String ordersItemQuantity(Object name, int quantity);

  /// MT: needs native review. Payment section card title on order details.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get ordersPayment;

  /// MT: needs native review. Label for credit amount applied to an order.
  ///
  /// In en, this message translates to:
  /// **'Credit Used'**
  String get ordersCreditUsed;

  /// MT: needs native review. First timeline node label (order created).
  ///
  /// In en, this message translates to:
  /// **'Order Placed'**
  String get ordersOrderPlaced;

  /// MT: needs native review. Tracking sheet section heading.
  ///
  /// In en, this message translates to:
  /// **'Order status'**
  String get ordersOrderStatus;

  /// Tracking headline showing the real road-route ETA from Directions.
  ///
  /// In en, this message translates to:
  /// **'Arriving in {eta}'**
  String ordersArrivingIn(String eta);

  /// MT: needs native review. Tracking headline subtitle when out for delivery.
  ///
  /// In en, this message translates to:
  /// **'Your order is on the way'**
  String get ordersOnTheWayHeadline;

  /// MT: needs native review. Tracking headline subtitle before dispatch.
  ///
  /// In en, this message translates to:
  /// **'We\'ll update you as it moves'**
  String get ordersWeWillUpdate;

  /// MT: needs native review. Snackbar when rider phone not yet available.
  ///
  /// In en, this message translates to:
  /// **'Contact appears once a rider is assigned.'**
  String get ordersContactWhenAssigned;

  /// MT: needs native review. Snackbar when tel: launch fails.
  ///
  /// In en, this message translates to:
  /// **'Could not open the dialer.'**
  String get ordersDialerError;

  /// MT: needs native review. Label above rider name on tracking.
  ///
  /// In en, this message translates to:
  /// **'Delivery Partner'**
  String get ordersDeliveryPartner;

  /// MT: needs native review. Fallback rider name until backend supplies one.
  ///
  /// In en, this message translates to:
  /// **'On the way'**
  String get ordersRiderOnTheWay;

  /// No description provided for @ordersPreparingYourOrder.
  ///
  /// In en, this message translates to:
  /// **'We\'re preparing your order'**
  String get ordersPreparingYourOrder;

  /// No description provided for @ordersDeliveryFailedHint.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t complete this delivery. Our team will be in touch about the next attempt.'**
  String get ordersDeliveryFailedHint;

  /// No description provided for @ordersOrderClosedHint.
  ///
  /// In en, this message translates to:
  /// **'This order is closed. You can review what was ordered below.'**
  String get ordersOrderClosedHint;

  /// MT: needs native review. Placeholder in tracking map area when no coords.
  ///
  /// In en, this message translates to:
  /// **'Live map appears once your delivery address has a pinned location.'**
  String get ordersMapUnavailable;

  /// MT: needs native review. Overflow count for order items list.
  ///
  /// In en, this message translates to:
  /// **'+{count} more'**
  String ordersMoreItems(int count);

  /// MT: needs native review. Snackbar after reorder adds items to cart.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item added to cart} other{{count} items added to cart}}'**
  String ordersItemsAddedToCart(int count);

  /// MT: needs native review. Snackbar when reorder finds nothing available.
  ///
  /// In en, this message translates to:
  /// **'Those items are unavailable right now'**
  String get ordersItemsUnavailable;

  /// MT: needs native review. Delivered-summary time row label.
  ///
  /// In en, this message translates to:
  /// **'Ordered at'**
  String get ordersOrderedAt;

  /// MT: needs native review. Delivered-summary time row label.
  ///
  /// In en, this message translates to:
  /// **'Delivered at'**
  String get ordersDeliveredAt;

  /// MT: needs native review. Snackbar after submitting order rating.
  ///
  /// In en, this message translates to:
  /// **'Thanks for the feedback!'**
  String get ordersFeedbackThanks;

  /// MT: needs native review. Header when feedback already given.
  ///
  /// In en, this message translates to:
  /// **'You rated this order'**
  String get ordersYouRated;

  /// MT: needs native review. Feedback card prompt title.
  ///
  /// In en, this message translates to:
  /// **'How was your delivery?'**
  String get ordersHowWasDelivery;

  /// MT: needs native review. Feedback card subtitle when agent name unknown.
  ///
  /// In en, this message translates to:
  /// **'Your feedback helps us improve.'**
  String get ordersFeedbackHelps;

  /// MT: needs native review. Feedback card subtitle naming the delivery agent.
  ///
  /// In en, this message translates to:
  /// **'{name} delivered this order.'**
  String ordersAgentDelivered(Object name);

  /// MT: needs native review. Optional comment field hint on feedback card.
  ///
  /// In en, this message translates to:
  /// **'Anything to add? (optional)'**
  String get ordersFeedbackHint;

  /// MT: needs native review. Submit button on feedback card.
  ///
  /// In en, this message translates to:
  /// **'Send feedback'**
  String get ordersSendFeedback;

  /// MT: needs native review. Accessibility label for star rating icons.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 star} other{{count} stars}}'**
  String ordersStarCount(int count);

  /// MT: needs native review. Logout confirmation dialog body.
  ///
  /// In en, this message translates to:
  /// **'You will need to sign in again to access your account.'**
  String get profileLogoutConfirmBody;

  /// MT: needs native review. Guest sign-in card title.
  ///
  /// In en, this message translates to:
  /// **'You\'re browsing as a guest'**
  String get profileBrowsingAsGuest;

  /// MT: needs native review. Guest sign-in card body.
  ///
  /// In en, this message translates to:
  /// **'Sign in to place orders, track deliveries and unlock VS Credit.'**
  String get profileGuestSignInBody;

  /// MT: needs native review. Fallback display name for a guest user.
  ///
  /// In en, this message translates to:
  /// **'Guest'**
  String get profileGuest;

  /// MT: needs native review. Compact available-credit chip on profile card.
  ///
  /// In en, this message translates to:
  /// **'Credit {amount}'**
  String profileCreditAmount(Object amount);

  /// MT: needs native review. Compact VS Score chip on profile card.
  ///
  /// In en, this message translates to:
  /// **'Score {score}'**
  String profileScoreValue(Object score);

  /// MT: needs native review. Credit used figure on available-credit card.
  ///
  /// In en, this message translates to:
  /// **'Used: {amount}'**
  String profileUsedAmount(Object amount);

  /// MT: needs native review. Credit limit figure on available-credit card.
  ///
  /// In en, this message translates to:
  /// **'Limit: {amount}'**
  String profileLimitAmount(Object amount);

  /// MT: needs native review. Quick-access tile label.
  ///
  /// In en, this message translates to:
  /// **'Addresses'**
  String get profileAddresses;

  /// MT: needs native review. Quick-access tile label.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get profilePayments;

  /// MT: needs native review. Quick-access tile label.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get profileSupport;

  /// MT: needs native review. Credit center row label.
  ///
  /// In en, this message translates to:
  /// **'Monthly Statement'**
  String get profileMonthlyStatement;

  /// MT: needs native review. Credit center row label.
  ///
  /// In en, this message translates to:
  /// **'Outstanding Due'**
  String get profileOutstandingDue;

  /// MT: needs native review. Credit center row label.
  ///
  /// In en, this message translates to:
  /// **'Credit Usage'**
  String get profileCreditUsage;

  /// MT: needs native review. Credit center row label.
  ///
  /// In en, this message translates to:
  /// **'VS Score Details'**
  String get profileVsScoreDetails;

  /// MT: needs native review. Address preview empty state.
  ///
  /// In en, this message translates to:
  /// **'No saved address yet.'**
  String get profileNoSavedAddress;

  /// MT: needs native review. Recent payments row label for UPI.
  ///
  /// In en, this message translates to:
  /// **'UPI Payment'**
  String get profilePaymentUpi;

  /// MT: needs native review. Recent payments row label for card.
  ///
  /// In en, this message translates to:
  /// **'Card Payment'**
  String get profilePaymentCard;

  /// MT: needs native review. Recent payments row label for bank transfer.
  ///
  /// In en, this message translates to:
  /// **'Bank Transfer'**
  String get profilePaymentBankTransfer;

  /// MT: needs native review. Recent payments row label for cash collection.
  ///
  /// In en, this message translates to:
  /// **'Cash Collection'**
  String get profilePaymentCashCollection;

  /// MT: needs native review. Recent payments card action.
  ///
  /// In en, this message translates to:
  /// **'View History'**
  String get profileViewHistory;

  /// MT: needs native review. KYC checklist item.
  ///
  /// In en, this message translates to:
  /// **'Aadhaar'**
  String get profileKycAadhaar;

  /// MT: needs native review. KYC checklist item.
  ///
  /// In en, this message translates to:
  /// **'Selfie'**
  String get profileKycSelfie;

  /// MT: needs native review. KYC checklist item.
  ///
  /// In en, this message translates to:
  /// **'House Verification'**
  String get profileKycHouse;

  /// MT: needs native review. Offers card subtitle showing active coupon count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 Active Coupon} other{{count} Active Coupons}}'**
  String profileActiveCoupons(int count);

  /// MT: needs native review. Settings list row; current UI shows fixed English label.
  ///
  /// In en, this message translates to:
  /// **'Language (English)'**
  String get profileLanguageEnglish;

  /// MT: needs native review. Settings list row (VS Mart is a brand name).
  ///
  /// In en, this message translates to:
  /// **'About VS Mart'**
  String get profileAboutVsMart;

  /// MT: needs native review. Settings list row.
  ///
  /// In en, this message translates to:
  /// **'Careers'**
  String get profileCareers;

  /// MT: needs native review. Primary family member display name.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get profileYou;

  /// MT: needs native review. Family member relationship label.
  ///
  /// In en, this message translates to:
  /// **'Primary Account Holder'**
  String get profilePrimaryHolder;

  /// MT: needs native review. Fallback family member display name.
  ///
  /// In en, this message translates to:
  /// **'Family Member'**
  String get profileFamilyMember;

  /// MT: needs native review. Family member status subtitle.
  ///
  /// In en, this message translates to:
  /// **'Invitation pending'**
  String get profileInvitationPending;

  /// MT: needs native review. Family member relationship subtitle.
  ///
  /// In en, this message translates to:
  /// **'Household member'**
  String get profileHouseholdMember;

  /// MT: needs native review. Snackbar after removing a family member.
  ///
  /// In en, this message translates to:
  /// **'{name} removed.'**
  String profileMemberRemoved(Object name);

  /// MT: needs native review. Add-member dialog relationship field hint.
  ///
  /// In en, this message translates to:
  /// **'Relationship (e.g. Spouse)'**
  String get profileRelationshipHint;

  /// MT: needs native review. Add-member dialog confirm button.
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get profileInvite;

  /// MT: needs native review. Snackbar after inviting a family member.
  ///
  /// In en, this message translates to:
  /// **'Invite sent to {phone}.'**
  String profileInviteSent(Object phone);

  /// MT: needs native review. Family screen error state.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load your household.'**
  String get profileHouseholdLoadError;

  /// MT: needs native review. Family screen intro paragraph.
  ///
  /// In en, this message translates to:
  /// **'Manage shared credit limits and shopping profiles for your family.'**
  String get profileFamilySubtitle;

  /// MT: needs native review. Family member card usage label.
  ///
  /// In en, this message translates to:
  /// **'Shared Limit Usage'**
  String get profileSharedLimitUsage;

  /// MT: needs native review. Add-member CTA card title.
  ///
  /// In en, this message translates to:
  /// **'Add a Household Member'**
  String get profileAddHouseholdMember;

  /// MT: needs native review. Add-member CTA card body (VS Mart is a brand name).
  ///
  /// In en, this message translates to:
  /// **'Invite family to share your VS Mart credit limit and shopping lists.'**
  String get profileAddMemberBody;

  /// MT: needs native review. Snackbar after saving profile.
  ///
  /// In en, this message translates to:
  /// **'Profile updated'**
  String get profileUpdated;

  /// MT: needs native review. Snackbar after avatar upload.
  ///
  /// In en, this message translates to:
  /// **'Profile photo updated.'**
  String get profilePhotoUpdated;

  /// MT: needs native review. Full name field example hint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Jane Doe'**
  String get profileNameHint;

  /// MT: needs native review. Email field example hint.
  ///
  /// In en, this message translates to:
  /// **'you@example.com'**
  String get profileEmailHint;

  /// MT: needs native review. Product detail error when id missing.
  ///
  /// In en, this message translates to:
  /// **'Product not found.'**
  String get catalogProductNotFound;

  /// MT: needs native review. Snackbar when un-wishlisting a product.
  ///
  /// In en, this message translates to:
  /// **'Removed from wishlist'**
  String get catalogRemovedFromWishlist;

  /// MT: needs native review. Snackbar when wishlisting a product.
  ///
  /// In en, this message translates to:
  /// **'Added to wishlist'**
  String get catalogAddedToWishlist;

  /// MT: needs native review. Snackbar when OS share sheet fails to open.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the share sheet.'**
  String get catalogShareSheetError;

  /// MT: needs native review. Fallback product description when none supplied.
  ///
  /// In en, this message translates to:
  /// **'Farm-fresh and hand-selected for quality, delivered at peak freshness.'**
  String get catalogDefaultDescription;

  /// MT: needs native review. Credit eligibility card title (VS Credit is a brand name).
  ///
  /// In en, this message translates to:
  /// **'Eligible for VS Credit'**
  String get catalogEligibleForCredit;

  /// MT: needs native review. Department fallback pane heading. name is category data.
  ///
  /// In en, this message translates to:
  /// **'Browse all in {name}'**
  String catalogBrowseAllIn(Object name);

  /// MT: needs native review. Department fallback pane button.
  ///
  /// In en, this message translates to:
  /// **'View products'**
  String get catalogViewProducts;

  /// MT: needs native review. Accessibility tooltip on quantity minus button.
  ///
  /// In en, this message translates to:
  /// **'Decrease quantity'**
  String get catalogDecreaseQuantity;

  /// MT: needs native review. Accessibility tooltip on quantity plus button.
  ///
  /// In en, this message translates to:
  /// **'Increase quantity'**
  String get catalogIncreaseQuantity;

  /// MT: needs native review. Listing header subtitle.
  ///
  /// In en, this message translates to:
  /// **'Handpicked daily from trusted farms'**
  String get catalogHandpickedDaily;

  /// MT: needs native review. Empty section title.
  ///
  /// In en, this message translates to:
  /// **'Nothing here'**
  String get catalogNothingHere;

  /// MT: needs native review. Subcategory banner eyebrow text.
  ///
  /// In en, this message translates to:
  /// **'Fresh picks in'**
  String get catalogFreshPicksIn;

  /// MT: needs native review. Subcategory banner subtitle.
  ///
  /// In en, this message translates to:
  /// **'Handpicked, quality-checked, delivered fast'**
  String get catalogHandpickedQuality;

  /// MT: needs native review. Snackbar after copying a product share link.
  ///
  /// In en, this message translates to:
  /// **'Share link copied'**
  String get catalogShareLinkCopied;

  /// MT: needs native review. Snackbar after adding a product to cart. name is product data.
  ///
  /// In en, this message translates to:
  /// **'{name} added to cart'**
  String catalogAddedToCart(Object name);

  /// MT: needs native review. Discount badge on price widget.
  ///
  /// In en, this message translates to:
  /// **'{percent}% OFF'**
  String catalogPercentOff(Object percent);

  /// MT: needs native review. Credit price line under a product price (VS Credit is a brand name). price is a formatted currency string.
  ///
  /// In en, this message translates to:
  /// **'{price} on VS Credit'**
  String catalogPriceOnCredit(Object price);

  /// MT: needs native review. Active price-filter chip label. min/max are formatted numbers.
  ///
  /// In en, this message translates to:
  /// **'₹{min} – ₹{max}'**
  String catalogPriceRange(Object min, Object max);

  /// MT: needs native review. Active discount-filter chip label.
  ///
  /// In en, this message translates to:
  /// **'{percent}%+ off'**
  String catalogDiscountOff(Object percent);

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Enter a valid 12-digit Aadhaar number'**
  String get verificationAadhaarInvalid;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'OTP sent to your Aadhaar-linked mobile'**
  String get verificationOtpSentAadhaar;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Enter the OTP you received'**
  String get verificationEnterOtpReceived;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Aadhaar verified'**
  String get verificationAadhaarVerified;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Could not capture image'**
  String get verificationCouldNotCaptureImage;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Please upload Aadhaar front and back'**
  String get verificationUploadAadhaarBoth;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Required to activate VS Credit.'**
  String get verificationRequiredForCredit;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Optional — only needed if you can\'t receive the OTP.'**
  String get verificationOtpOptionalNote;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Aadhaar Front'**
  String get verificationAadhaarFront;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Aadhaar Back'**
  String get verificationAadhaarBack;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Can\'t receive OTP? Continue with documents'**
  String get verificationCantReceiveOtp;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'We use Aadhaar verification to:'**
  String get verificationWhyAadhaarTitle;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Our team is reviewing your details. Your credit limit will reflect in your profile once approved.'**
  String get verificationReviewingDetails;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Credit reflection may take up to 2–4 hours after approval.'**
  String get verificationCreditReflectionNote;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Please complete all selections'**
  String get verificationCompleteSelections;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Help us determine your credit eligibility.'**
  String get verificationHelpDetermineEligibility;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Household'**
  String get verificationHousehold;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Draft saved'**
  String get verificationDraftSaved;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Based on initial profile assessment.'**
  String get verificationInitialAssessment;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Please upload all required documents'**
  String get verificationUploadAllDocs;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'We use your documents to:'**
  String get verificationWhyDocumentsTitle;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Please allow us to verify your PAN to continue'**
  String get verificationPanConsentRequired;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'PAN verified'**
  String get verificationPanVerified;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Your PAN is required for financial compliance.'**
  String get verificationPanComplianceNote;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Risk Evaluation'**
  String get verificationRiskEvaluation;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'I consent to VS Mart verifying my PAN with the Income Tax department for KYC.'**
  String get verificationPanConsentText;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Verify PAN'**
  String get verificationVerifyPan;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Please submit your details.'**
  String get verificationSubmitYourDetails;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Residence photo attached.'**
  String get verificationResidencePhotoAttached;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Could not access the camera/gallery.'**
  String get verificationCameraGalleryError;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Please add a photo of your residence.'**
  String get verificationAddResidencePhoto;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Capture your location before submitting.'**
  String get verificationCaptureLocationFirst;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Residence verification submitted.'**
  String get verificationResidenceSubmitted;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Please upload a clear photo of your residence to verify your address for faster processing and secure deliveries.'**
  String get verificationResidenceIntro;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Sample Approved Image'**
  String get verificationSampleApprovedImage;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Ideal'**
  String get verificationIdeal;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Latitude'**
  String get verificationLatitude;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Longitude'**
  String get verificationLongitude;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Submission failed. Please try again.'**
  String get verificationSubmissionFailed;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get verificationAddress;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Selfie'**
  String get verificationSelfie;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Credit Information'**
  String get verificationCreditInformation;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'House'**
  String get verificationHouse;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Complete all sections to submit your application.'**
  String get verificationCompleteAllSections;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Application Submitted'**
  String get verificationApplicationSubmitted;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Credit eligibility decision'**
  String get verificationCreditDecision;

  /// MT: needs native review. {id} is the application reference id.
  ///
  /// In en, this message translates to:
  /// **'Application {id}'**
  String verificationApplicationRef(Object id);

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'We\'ll notify you the moment a decision is made. You can keep browsing in the meantime.'**
  String get verificationNotifyDecision;

  /// MT: needs native review. {title} is the document name being uploaded.
  ///
  /// In en, this message translates to:
  /// **'Uploading {title}…'**
  String verificationUploading(Object title);

  /// MT: needs native review. Small caption under a credit-limit amount.
  ///
  /// In en, this message translates to:
  /// **'limit'**
  String get verificationLimitLabel;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Capture failed'**
  String get verificationCaptureFailed;

  /// MT: needs native review
  ///
  /// In en, this message translates to:
  /// **'Selfie captured'**
  String get verificationSelfieCaptured;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'hi', 'te'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'hi':
      return AppLocalizationsHi();
    case 'te':
      return AppLocalizationsTe();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
