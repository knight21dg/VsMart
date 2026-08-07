// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appTagline => 'मिनटों में किराना';

  @override
  String get commonOk => 'ठीक है';

  @override
  String get commonCancel => 'रद्द करें';

  @override
  String get commonClose => 'बंद करें';

  @override
  String get commonRetry => 'फिर से कोशिश करें';

  @override
  String get commonApply => 'लागू करें';

  @override
  String get commonSave => 'सहेजें';

  @override
  String get commonContinue => 'जारी रखें';

  @override
  String get commonNext => 'आगे';

  @override
  String get commonBack => 'वापस';

  @override
  String get commonDone => 'हो गया';

  @override
  String get commonYes => 'हाँ';

  @override
  String get commonNo => 'नहीं';

  @override
  String get commonSearch => 'खोजें';

  @override
  String get commonSeeAll => 'सभी देखें';

  @override
  String get commonLoading => 'लोड हो रहा है…';

  @override
  String get commonSomethingWentWrong => 'कुछ गलत हो गया';

  @override
  String get commonNoInternet => 'इंटरनेट कनेक्शन नहीं है';

  @override
  String get commonTryAgain => 'कृपया फिर से प्रयास करें';

  @override
  String get navHome => 'होम';

  @override
  String get navCategories => 'श्रेणियाँ';

  @override
  String get navCart => 'कार्ट';

  @override
  String get navOrders => 'ऑर्डर';

  @override
  String get navAccount => 'खाता';

  @override
  String get navCredit => 'VS क्रेडिट';

  @override
  String get homeSearchHint => 'किराना, ब्रांड और बहुत कुछ खोजें';

  @override
  String get homeDeliverTo => 'यहाँ डिलीवरी';

  @override
  String get homeOffersForYou => 'आपके लिए ऑफ़र';

  @override
  String get homeRecommended => 'आपके लिए अनुशंसित';

  @override
  String get homePopular => 'आपके पास लोकप्रिय';

  @override
  String get homeShopByCategory => 'श्रेणी के अनुसार खरीदें';

  @override
  String serviceDeliveringIn(int minutes) {
    return '$minutes मिनट में डिलीवरी';
  }

  @override
  String serviceFrom(String store) {
    return '$store से';
  }

  @override
  String get serviceNotAvailableTitle =>
      'हम अभी आपके क्षेत्र में उपलब्ध नहीं हैं';

  @override
  String get serviceNotAvailableBody =>
      'VS Mart फ़िलहाल इस स्थान पर डिलीवरी नहीं करता। हमें बताएं आप कहाँ हैं, और हम लॉन्च होने पर आपको सूचित करेंगे।';

  @override
  String get serviceChangeLocation => 'स्थान बदलें';

  @override
  String get serviceNotifyMe => 'मुझे सूचित करें';

  @override
  String get serviceStoreClosed => 'स्टोर अभी बंद है';

  @override
  String serviceStoreClosedResumesAt(String time) {
    return 'स्टोर बंद है। ऑर्डर $time बजे फिर से शुरू होंगे।';
  }

  @override
  String get serviceSlotsFull => 'आज के डिलीवरी स्लॉट भर गए हैं';

  @override
  String get productAddToCart => 'कार्ट में जोड़ें';

  @override
  String get productAdded => 'जोड़ा गया';

  @override
  String get productOutOfStock => 'स्टॉक ख़त्म';

  @override
  String get productInCart => 'कार्ट में';

  @override
  String productSave(String amount) {
    return '$amount बचाएं';
  }

  @override
  String get cartTitle => 'मेरा कार्ट';

  @override
  String get cartEmptyTitle => 'आपका कार्ट खाली है';

  @override
  String get cartEmptyBody => 'शुरू करने के लिए आइटम जोड़ें';

  @override
  String get cartSubtotal => 'उप-योग';

  @override
  String get cartDeliveryFee => 'डिलीवरी शुल्क';

  @override
  String get cartGst => 'GST';

  @override
  String get cartTotal => 'कुल';

  @override
  String get cartFree => 'मुफ़्त';

  @override
  String cartItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count आइटम',
      one: '1 आइटम',
      zero: 'कोई आइटम नहीं',
    );
    return '$_temp0';
  }

  @override
  String get cartProceedToCheckout => 'चेकआउट करें';

  @override
  String get checkoutTitle => 'चेकआउट';

  @override
  String get checkoutDeliveryAddress => 'डिलीवरी पता';

  @override
  String get checkoutPaymentMethod => 'भुगतान का तरीका';

  @override
  String get checkoutPlaceOrder => 'ऑर्डर करें';

  @override
  String get checkoutPayNow => 'अभी भुगतान करें';

  @override
  String get checkoutCod => 'डिलीवरी पर नकद';

  @override
  String get checkoutUpi => 'UPI';

  @override
  String get checkoutCard => 'कार्ड';

  @override
  String get checkoutVsCredit => 'VS क्रेडिट';

  @override
  String get checkoutOrderPlacedTitle => 'ऑर्डर हो गया!';

  @override
  String checkoutOrderPlacedBody(String code) {
    return 'आपका ऑर्डर $code दे दिया गया है।';
  }

  @override
  String get creditTitle => 'VS क्रेडिट';

  @override
  String get creditLimit => 'क्रेडिट सीमा';

  @override
  String get creditAvailable => 'उपलब्ध क्रेडिट';

  @override
  String get creditOutstanding => 'बकाया';

  @override
  String creditOutstandingAmount(String amount) {
    return 'आपके पास $amount बकाया है';
  }

  @override
  String creditDueOn(String date) {
    return '$date तक देय';
  }

  @override
  String get creditRepay => 'चुकाएं';

  @override
  String get creditRepayNow => 'अभी चुकाएं';

  @override
  String get creditPayBill => 'बिल भुगतान करें';

  @override
  String get creditFrozen => 'आपका क्रेडिट अस्थायी रूप से रोक दिया गया है';

  @override
  String get creditCompleteKyc => 'VS क्रेडिट उपयोग करने के लिए KYC पूरा करें';

  @override
  String get kycTitle => 'सत्यापन';

  @override
  String get kycCompleteTitle => 'अपना KYC पूरा करें';

  @override
  String get kycPending => 'सत्यापन प्रगति पर है';

  @override
  String get kycVerified => 'सत्यापित';

  @override
  String get kycRejected => 'सत्यापन अस्वीकृत';

  @override
  String get kycUploadDocument => 'दस्तावेज़ अपलोड करें';

  @override
  String get kycVerifyIdentity => 'पहचान सत्यापित करें';

  @override
  String get ordersTitle => 'मेरे ऑर्डर';

  @override
  String get ordersEmpty => 'आपके पास अभी कोई ऑर्डर नहीं है';

  @override
  String get ordersTrack => 'ऑर्डर ट्रैक करें';

  @override
  String get reorderSheetTitle => 'इन्हें अपने कार्ट में जोड़ें?';

  @override
  String reorderAddAll(int count) {
    return '$count कार्ट में जोड़ें';
  }

  @override
  String get reorderUnavailableHeading => 'अभी उपलब्ध नहीं';

  @override
  String get reorderDiscontinued => 'अब नहीं बेचा जाता';

  @override
  String get reorderOutOfStock => 'स्टॉक में नहीं';

  @override
  String get reorderNothingAvailable =>
      'इनमें से कोई भी वस्तु अभी उपलब्ध नहीं है।';

  @override
  String get reorderPricesMayHaveChanged => 'दिखाई गई कीमतें आज की हैं।';

  @override
  String get ordersAmountPaid => 'भुगतान की गई राशि';

  @override
  String get ordersAmountRefunded => 'वापस किया गया';

  @override
  String get ordersRefundPending => 'रिफ़ंड अभी जारी नहीं हुआ';

  @override
  String get deliveryOtpTitle => 'डिलीवरी OTP';

  @override
  String get deliveryOtpShare => 'यह कोड दरवाज़े पर अपने राइडर को बताएं';

  @override
  String get profileOrderArriving => 'आपका ऑर्डर आ रहा है';

  @override
  String get profileShowOtp =>
      'ट्रैक करने और डिलीवरी OTP देखने के लिए टैप करें';

  @override
  String get ordersReorder => 'फिर से ऑर्डर करें';

  @override
  String get orderStatusPending => 'लंबित';

  @override
  String get orderStatusConfirmed => 'पुष्ट';

  @override
  String get orderStatusPacked => 'पैक किया गया';

  @override
  String get orderStatusOutForDelivery => 'डिलीवरी के लिए निकला';

  @override
  String get orderStatusDelivered => 'डिलीवर हो गया';

  @override
  String get orderStatusCancelled => 'रद्द किया गया';

  @override
  String get accountTitle => 'खाता';

  @override
  String get accountSettings => 'सेटिंग्स';

  @override
  String get accountLanguage => 'भाषा';

  @override
  String get accountLogout => 'लॉग आउट';

  @override
  String get languageTitle => 'भाषा';

  @override
  String get languageSelect => 'भाषा चुनें';

  @override
  String get languageCurrent => 'वर्तमान भाषा';

  @override
  String get languageApply => 'भाषा लागू करें';

  @override
  String get languageUpdated => 'भाषा अपडेट हुई';

  @override
  String get languagePreview => 'भाषा पूर्वावलोकन';

  @override
  String get codeOutsideServiceAreaTitle => 'सेवा अनुपलब्ध';

  @override
  String get codeOutsideServiceAreaBody =>
      'VS Mart फ़िलहाल आपके स्थान पर डिलीवरी नहीं करता।';

  @override
  String get codeStoreClosedTitle => 'स्टोर बंद';

  @override
  String get codeStoreClosedBody =>
      'आपके क्षेत्र का स्टोर अभी ऑर्डर स्वीकार नहीं कर रहा है।';

  @override
  String get codeCapacityReachedTitle => 'डिलीवरी स्लॉट भरे';

  @override
  String get codeCapacityReachedBody =>
      'आपके क्षेत्र की आज की डिलीवरी क्षमता भर गई है। कृपया कल पुनः प्रयास करें।';

  @override
  String get codeStoreChangedTitle => 'डिलीवरी क्षेत्र बदला';

  @override
  String get codeStoreChangedBody =>
      'आपका डिलीवरी पता किसी दूसरे स्टोर के क्षेत्र में चला गया, इसलिए आपका कार्ट रिफ्रेश कर दिया गया।';

  @override
  String get codeProductUnavailableTitle => 'आपके स्टोर पर उपलब्ध नहीं';

  @override
  String get codeProductUnavailableBody =>
      'आपके कार्ट के कुछ आइटम आपके क्षेत्र के स्टोर पर उपलब्ध नहीं हैं।';

  @override
  String get codeOutOfStockTitle => 'आइटम अनुपलब्ध';

  @override
  String get codeOutOfStockBody =>
      'आपके कार्ट में एक या अधिक आइटम स्टॉक में नहीं हैं।';

  @override
  String get codeKycRequiredTitle => 'सत्यापन आवश्यक';

  @override
  String get codeKycRequiredBody =>
      'VS क्रेडिट से भुगतान से पहले KYC पूरा करें।';

  @override
  String get codeCreditDisabledTitle => 'क्रेडिट अनुपलब्ध';

  @override
  String get codeCreditDisabledBody =>
      'इस ऑर्डर के लिए VS क्रेडिट उपलब्ध नहीं है।';

  @override
  String get codeLimitExceededTitle => 'सीमा पार';

  @override
  String get codeLimitExceededBody =>
      'यह ऑर्डर आपकी उपलब्ध क्रेडिट से अधिक है।';

  @override
  String get codeOverduePaymentTitle => 'भुगतान अतिदेय';

  @override
  String get codeOverduePaymentBody =>
      'नया क्रेडिट ऑर्डर देने से पहले अपना अतिदेय बकाया चुकाएं।';

  @override
  String get codeSessionExpiredTitle => 'सत्र समाप्त';

  @override
  String get codeSessionExpiredBody =>
      'जारी रखने के लिए कृपया पुनः साइन इन करें।';

  @override
  String get commonEdit => 'संपादित करें';

  @override
  String get commonDelete => 'हटाएं';

  @override
  String get commonRemove => 'हटाएं';

  @override
  String get commonUpdate => 'अपडेट करें';

  @override
  String get commonConfirm => 'पुष्टि करें';

  @override
  String get commonSubmit => 'सबमिट करें';

  @override
  String get commonShare => 'शेयर करें';

  @override
  String get commonViewDetails => 'विवरण देखें';

  @override
  String get commonViewAll => 'सभी देखें';

  @override
  String get commonChange => 'बदलें';

  @override
  String get commonAdd => 'जोड़ें';

  @override
  String get commonProceed => 'आगे बढ़ें';

  @override
  String get commonSkip => 'छोड़ें';

  @override
  String get commonRefresh => 'रिफ्रेश करें';

  @override
  String get commonClearAll => 'सभी साफ़ करें';

  @override
  String get commonComingSoon => 'जल्द आ रहा है';

  @override
  String get commonNoData => 'यहाँ अभी कुछ नहीं है';

  @override
  String get authWelcome => 'VS Mart में आपका स्वागत है';

  @override
  String get authEnterPhone => 'अपना मोबाइल नंबर दर्ज करें';

  @override
  String get authPhoneHint => 'मोबाइल नंबर';

  @override
  String get authSendOtp => 'OTP भेजें';

  @override
  String get authEnterOtp => 'OTP दर्ज करें';

  @override
  String authOtpSentTo(String phone) {
    return '$phone पर OTP भेजा गया';
  }

  @override
  String get authVerify => 'सत्यापित करें';

  @override
  String get authResendOtp => 'OTP फिर से भेजें';

  @override
  String authResendIn(int seconds) {
    return '$secondsसे में फिर से भेजें';
  }

  @override
  String get authTermsAgree =>
      'जारी रखकर आप हमारी शर्तों और गोपनीयता नीति से सहमत होते हैं';

  @override
  String get authLoginToContinue => 'जारी रखने के लिए लॉग इन करें';

  @override
  String get accountEditProfile => 'प्रोफ़ाइल संपादित करें';

  @override
  String get accountMyAddresses => 'मेरे पते';

  @override
  String get accountPaymentMethods => 'भुगतान के तरीके';

  @override
  String get accountHelpSupport => 'सहायता और समर्थन';

  @override
  String get accountAboutUs => 'हमारे बारे में';

  @override
  String get accountTerms => 'नियम और शर्तें';

  @override
  String get accountPrivacy => 'गोपनीयता नीति';

  @override
  String get accountRateUs => 'हमें रेट करें';

  @override
  String get accountShareApp => 'ऐप शेयर करें';

  @override
  String get accountDeleteAccount => 'खाता हटाएं';

  @override
  String accountVersion(String version) {
    return 'वर्शन $version';
  }

  @override
  String get accountPersonalDetails => 'व्यक्तिगत विवरण';

  @override
  String get accountName => 'नाम';

  @override
  String get accountEmail => 'ईमेल';

  @override
  String get accountPhone => 'फ़ोन';

  @override
  String get accountSaveChanges => 'परिवर्तन सहेजें';

  @override
  String get orderDetailsTitle => 'ऑर्डर विवरण';

  @override
  String get orderId => 'ऑर्डर ID';

  @override
  String orderPlacedOn(String date) {
    return '$date को दिया गया';
  }

  @override
  String get orderItems => 'आइटम';

  @override
  String get orderBillDetails => 'बिल विवरण';

  @override
  String get orderDownloadInvoice => 'इनवॉइस डाउनलोड करें';

  @override
  String get orderNeedHelp => 'मदद चाहिए?';

  @override
  String get orderCancel => 'ऑर्डर रद्द करें';

  @override
  String get orderRate => 'ऑर्डर रेट करें';

  @override
  String get orderSummary => 'ऑर्डर सारांश';

  @override
  String get orderDeliveryDetails => 'डिलीवरी विवरण';

  @override
  String get orderItemTotal => 'आइटम कुल';

  @override
  String get orderGrandTotal => 'कुल योग';

  @override
  String orderSaved(String amount) {
    return 'आपने $amount बचाए';
  }

  @override
  String get creditStatements => 'स्टेटमेंट';

  @override
  String get creditPaymentHistory => 'भुगतान इतिहास';

  @override
  String get creditRepayment => 'पुनर्भुगतान';

  @override
  String get creditDueDate => 'देय तिथि';

  @override
  String get creditMinimumDue => 'न्यूनतम देय';

  @override
  String get creditTotalDue => 'कुल देय';

  @override
  String get creditTransactionHistory => 'लेन-देन इतिहास';

  @override
  String get creditScore => 'VS स्कोर';

  @override
  String get creditUsed => 'उपयोग किया गया';

  @override
  String get creditRepaymentPlan => 'पुनर्भुगतान योजना';

  @override
  String get creditWeekend => 'सप्ताहांत';

  @override
  String get creditMonthEnd => 'महीने का अंत';

  @override
  String get creditPayFull => 'पूरी राशि चुकाएं';

  @override
  String get creditNoDues => 'आपका कोई बकाया नहीं है';

  @override
  String get checkoutSelectAddress => 'डिलीवरी पता चुनें';

  @override
  String get checkoutAddNewAddress => 'नया पता जोड़ें';

  @override
  String get checkoutApplyCoupon => 'कूपन लगाएं';

  @override
  String get checkoutCouponApplied => 'कूपन लागू किया गया';

  @override
  String get checkoutBillSummary => 'बिल सारांश';

  @override
  String get checkoutItemTotal => 'आइटम कुल';

  @override
  String get checkoutSavings => 'बचत';

  @override
  String get checkoutGrandTotal => 'कुल योग';

  @override
  String get checkoutPaymentOptions => 'भुगतान विकल्प';

  @override
  String get checkoutDeliverySlot => 'डिलीवरी स्लॉट';

  @override
  String get addressAdd => 'पता जोड़ें';

  @override
  String get addressEdit => 'पता संपादित करें';

  @override
  String get addressFullName => 'पूरा नाम';

  @override
  String get addressPhone => 'फ़ोन नंबर';

  @override
  String get addressPincode => 'पिनकोड';

  @override
  String get addressHouseNo => 'मकान / फ्लैट नं.';

  @override
  String get addressArea => 'क्षेत्र / इलाका';

  @override
  String get addressLandmark => 'लैंडमार्क';

  @override
  String get addressCity => 'शहर';

  @override
  String get addressState => 'राज्य';

  @override
  String get addressSave => 'पता सहेजें';

  @override
  String get addressSetDefault => 'डिफ़ॉल्ट के रूप में सेट करें';

  @override
  String get addressType => 'पते का प्रकार';

  @override
  String get addressHome => 'घर';

  @override
  String get addressWork => 'ऑफिस';

  @override
  String get addressOther => 'अन्य';

  @override
  String get addressUseCurrentLocation => 'वर्तमान स्थान का उपयोग करें';

  @override
  String get addressNone => 'कोई सहेजा गया पता नहीं';

  @override
  String get notificationsTitle => 'सूचनाएं';

  @override
  String get notificationsMarkAllRead => 'सभी को पढ़ा हुआ चिह्नित करें';

  @override
  String get notificationsEmpty => 'अभी कोई सूचना नहीं';

  @override
  String get notificationsToday => 'आज';

  @override
  String get notificationsEarlier => 'पहले';

  @override
  String get supportTitle => 'सहायता और समर्थन';

  @override
  String get supportContactUs => 'संपर्क करें';

  @override
  String get supportFaqs => 'अक्सर पूछे जाने वाले प्रश्न';

  @override
  String get supportRaiseTicket => 'टिकट बनाएं';

  @override
  String get supportMyTickets => 'मेरे टिकट';

  @override
  String get supportChat => 'हमसे चैट करें';

  @override
  String get supportCall => 'हमें कॉल करें';

  @override
  String get supportEmail => 'हमें ईमेल करें';

  @override
  String get searchTitle => 'खोजें';

  @override
  String get searchHint => 'उत्पाद खोजें';

  @override
  String get searchNoResults => 'कोई परिणाम नहीं मिला';

  @override
  String get searchRecent => 'हाल की खोजें';

  @override
  String get searchPopular => 'लोकप्रिय खोजें';

  @override
  String searchResultsFor(String query) {
    return '\"$query\" के लिए परिणाम';
  }

  @override
  String get settingsTitle => 'सेटिंग्स';

  @override
  String get settingsTheme => 'थीम';

  @override
  String get settingsDarkMode => 'डार्क मोड';

  @override
  String get settingsLightMode => 'लाइट मोड';

  @override
  String get settingsSystemDefault => 'सिस्टम डिफ़ॉल्ट';

  @override
  String get settingsNotifications => 'सूचनाएं';

  @override
  String get settingsPrivacy => 'गोपनीयता और सुरक्षा';

  @override
  String get kycStartCta => 'सत्यापन शुरू करें';

  @override
  String get kycSubmitForReview => 'समीक्षा के लिए सबमिट करें';

  @override
  String get orderStatusDraft => 'ड्राफ्ट';

  @override
  String get orderStatusPlaced => 'ऑर्डर किया गया';

  @override
  String get orderStatusReadyForDispatch => 'डिस्पैच के लिए तैयार';

  @override
  String get orderStatusRejected => 'अस्वीकृत';

  @override
  String get orderStatusReturned => 'वापस किया गया';

  @override
  String get orderStatusPartiallyReturned => 'आंशिक रूप से वापस';

  @override
  String get orderStatusFailedDelivery => 'डिलीवरी विफल';

  @override
  String get payStatusPaid => 'भुगतान हो गया';

  @override
  String get payStatusFailed => 'विफल';

  @override
  String get payStatusRefunded => 'रिफंड किया गया';

  @override
  String get verifyStatusNotStarted => 'शुरू नहीं हुआ';

  @override
  String get verifyStatusDraft => 'ड्राफ्ट';

  @override
  String get verifyStatusPending => 'लंबित';

  @override
  String get verifyStatusUnderReview => 'समीक्षाधीन';

  @override
  String get verifyStatusApproved => 'स्वीकृत';

  @override
  String get verifyStatusRejected => 'अस्वीकृत';

  @override
  String get kycNotStarted => 'शुरू नहीं हुआ';

  @override
  String get kycDocAadhaar => 'आधार कार्ड';

  @override
  String get kycDocPan => 'पैन कार्ड';

  @override
  String get kycDocSelfie => 'सेल्फी / वीडियो KYC';

  @override
  String get kycDocResidence => 'पते का प्रमाण';

  @override
  String get catalogAll => 'सभी';

  @override
  String get catalogApplyFilters => 'फ़िल्टर लागू करें';

  @override
  String get catalogBrand => 'ब्रांड';

  @override
  String get catalogDescription => 'विवरण';

  @override
  String get catalogFilter => 'फ़िल्टर';

  @override
  String get catalogFilters => 'फ़िल्टर';

  @override
  String get catalogGoToCart => 'कार्ट पर जाएं';

  @override
  String get catalogInStock => 'स्टॉक में';

  @override
  String get catalogInStockOnly => 'केवल स्टॉक में';

  @override
  String get catalogMinDiscount => 'न्यूनतम छूट';

  @override
  String get catalogNoCategories => 'कोई श्रेणी नहीं मिली';

  @override
  String get catalogNoProducts => 'कोई उत्पाद नहीं';

  @override
  String get catalogNoProductsFound => 'कोई उत्पाद नहीं मिला';

  @override
  String get catalogPrice => 'कीमत';

  @override
  String get catalogProductDetails => 'उत्पाद विवरण';

  @override
  String get catalogProducts => 'उत्पाद';

  @override
  String get catalogQuantity => 'मात्रा';

  @override
  String get catalogSearchCategories => 'श्रेणियाँ खोजें';

  @override
  String get catalogSelectVariation => 'वैरिएंट चुनें';

  @override
  String get catalogSort => 'क्रमबद्ध करें';

  @override
  String get catalogSortBy => 'इसके अनुसार क्रमबद्ध करें';

  @override
  String get catalogSpecifications => 'विशिष्टताएं';

  @override
  String get catalogNoProductsInCategory =>
      'इस श्रेणी में अभी कोई उत्पाद नहीं है।';

  @override
  String get catalogAdjustFilters => 'अपने फ़िल्टर या खोज को समायोजित करें।';

  @override
  String get catalogViewCart => 'कार्ट देखें';

  @override
  String get catalogYouMayAlsoLike => 'आपको यह भी पसंद आ सकता है';

  @override
  String catalogReviews(int count) {
    return '$count समीक्षाएं';
  }

  @override
  String get catalogBuyNowPayLater =>
      'अभी खरीदें, बिना ब्याज बाद में भुगतान करें।';

  @override
  String get homeExploreCategories => 'श्रेणियाँ देखें';

  @override
  String get homePopularProducts => 'लोकप्रिय उत्पाद';

  @override
  String get homeRecentlyOrdered => 'हाल में ऑर्डर किया';

  @override
  String get homeShopNow => 'अभी खरीदें';

  @override
  String get homeContinueShopping => 'खरीदारी जारी रखें';

  @override
  String get homeEnableLocation => 'स्थान सक्षम करें';

  @override
  String get homeSpecialSale => 'विशेष सेल 🔥';

  @override
  String get homeTapToTrack => 'अपना ऑर्डर ट्रैक करने के लिए टैप करें';

  @override
  String get authCreateAccount => 'खाता बनाएं';

  @override
  String get authVerifyContinue => 'सत्यापित करें और जारी रखें';

  @override
  String get authVerifiedNumber => 'सत्यापित नंबर';

  @override
  String get authUseDifferentNumber => 'दूसरा नंबर उपयोग करें';

  @override
  String get authReferralCode => 'रेफरल कोड';

  @override
  String get commonOptional => 'वैकल्पिक';

  @override
  String get authAlmostThere => 'बस हो गया!';

  @override
  String get authWantCredit => 'अभी खरीदें बाद में भुगतान करना चाहते हैं?';

  @override
  String get authTermsOfService => 'सेवा की शर्तें';

  @override
  String get authGoToHome => 'होम पर जाएं';

  @override
  String get billingPurchase => 'खरीद';

  @override
  String get billingPenalty => 'जुर्माना';

  @override
  String get billingAdjustment => 'समायोजन';

  @override
  String get billingRefund => 'रिफंड';

  @override
  String get billingCompleted => 'पूर्ण';

  @override
  String get billingReversed => 'वापस किया गया';

  @override
  String get billingOverdue => 'अतिदेय';

  @override
  String get billingAssigned => 'सौंपा गया';

  @override
  String get billingBankTransfer => 'बैंक ट्रांसफर';

  @override
  String get billingCashCollection => 'नकद संग्रह';

  @override
  String get billingInvoices => 'इनवॉइस';

  @override
  String get billingInvoice => 'इनवॉइस';

  @override
  String get billingStatement => 'स्टेटमेंट';

  @override
  String get billingTransactions => 'लेन-देन';

  @override
  String get billingMakePayment => 'भुगतान करें';

  @override
  String get billingEnterAmount => 'राशि दर्ज करें';

  @override
  String get billingAmount => 'राशि';

  @override
  String get billingAmountDue => 'देय राशि';

  @override
  String get billingAmountPaid => 'भुगतान की गई राशि';

  @override
  String get billingPayNow => 'अभी भुगतान करें';

  @override
  String get billingDate => 'तारीख';

  @override
  String get billingStatus => 'स्थिति';

  @override
  String get billingMethod => 'तरीका';

  @override
  String get billingReference => 'संदर्भ';

  @override
  String get billingNotes => 'नोट्स (वैकल्पिक)';

  @override
  String get billingDownloadReceipt => 'रसीद डाउनलोड करें';

  @override
  String get commonDownload => 'डाउनलोड';

  @override
  String get billingViewOrder => 'ऑर्डर देखें';

  @override
  String get billingViewStatement => 'स्टेटमेंट देखें';

  @override
  String get billingRequestCollection => 'संग्रह का अनुरोध करें';

  @override
  String get billingCollections => 'संग्रह';

  @override
  String get billingCollected => 'एकत्रित';

  @override
  String get billingAgent => 'एजेंट';

  @override
  String get billingPaymentSuccessful => 'भुगतान सफल';

  @override
  String get billingTotalOutstanding => 'कुल बकाया';

  @override
  String get billingTotalAmountDue => 'कुल देय राशि';

  @override
  String get billingCurrentBill => 'वर्तमान बिल';

  @override
  String get billingRecentActivity => 'हाल की गतिविधि';

  @override
  String get billingBreakdown => 'विवरण';

  @override
  String get billingPrincipal => 'मूलधन';

  @override
  String get billingInterest => 'ब्याज';

  @override
  String get billingLateFee => 'विलंब शुल्क';

  @override
  String get billingInvoiceNumber => 'इनवॉइस नंबर';

  @override
  String get billingInvoiceDate => 'इनवॉइस तारीख';

  @override
  String get billingCreditSummary => 'क्रेडिट सारांश';

  @override
  String get billingBackToDashboard => 'डैशबोर्ड पर वापस';

  @override
  String get billingNoInvoices => 'अभी कोई इनवॉइस नहीं';

  @override
  String get billingNoPayments => 'अभी कोई भुगतान नहीं';

  @override
  String get billingNoStatements => 'अभी कोई स्टेटमेंट नहीं';

  @override
  String get billingNoCollections => 'कोई संग्रह अनुरोध नहीं';

  @override
  String get billingNoTransactions => 'अभी कोई लेन-देन नहीं';

  @override
  String get billingAllCaughtUp => 'सब पूरा हो गया';

  @override
  String get billingNoPendingDues => 'आपका अभी कोई बकाया नहीं है।';

  @override
  String get billingInvoicesAppearHere =>
      'आपके क्रेडिट ऑर्डर के इनवॉइस यहाँ दिखेंगे।';

  @override
  String get billingStatementsAppearHere =>
      'आपके बिलिंग स्टेटमेंट यहाँ दिखेंगे।';

  @override
  String get billingRepaymentsAppearHere => 'आपके पुनर्भुगतान यहाँ दिखेंगे।';

  @override
  String get billingRepaymentRecorded =>
      'आपका पुनर्भुगतान दर्ज कर लिया गया है।';

  @override
  String get billingSecurePayments => '100% सुरक्षित भुगतान';

  @override
  String get billingInvoiceNotFound => 'इनवॉइस नहीं मिला';

  @override
  String get billingStatementNotFound => 'स्टेटमेंट नहीं मिला';

  @override
  String get profileTitle => 'प्रोफ़ाइल';

  @override
  String get profileQuickAccess => 'त्वरित पहुंच';

  @override
  String get profileCreditCenter => 'क्रेडिट केंद्र';

  @override
  String get profileRecentOrders => 'हाल के ऑर्डर';

  @override
  String get profileRecentPayments => 'हाल के भुगतान';

  @override
  String get profileNoOrders => 'अभी कोई ऑर्डर नहीं';

  @override
  String get profileNotSignedIn => 'साइन इन नहीं किया';

  @override
  String get profileSignInPrompt =>
      'अपनी प्रोफ़ाइल देखने और संपादित करने के लिए साइन इन करें।';

  @override
  String get profileSignInCreate => 'साइन इन / खाता बनाएं';

  @override
  String get profilePayDue => 'बकाया चुकाएं';

  @override
  String get profileManageAddresses => 'पते प्रबंधित करें';

  @override
  String get profileMyReturns => 'मेरे रिटर्न';

  @override
  String get profileRewards => 'रिवॉर्ड';

  @override
  String get profileReferEarn => 'रेफर करें और कमाएं';

  @override
  String get profileOffersRewards => 'ऑफ़र और रिवॉर्ड';

  @override
  String get profileViewOffers => 'ऑफ़र देखें';

  @override
  String get profileFaqHelp => 'FAQ और सहायता';

  @override
  String get profileGender => 'लिंग';

  @override
  String get profileDob => 'जन्म तिथि';

  @override
  String get profileChangeNumberNote =>
      'अपना सत्यापित नंबर बदलने के लिए, सहायता से संपर्क करें।';

  @override
  String get profileKycStatus => 'KYC स्थिति';

  @override
  String get profileFamilyInfo => 'परिवार की जानकारी';

  @override
  String get profileHouseholdMembers => 'परिवार के सदस्य';

  @override
  String get profileAddMember => 'सदस्य जोड़ें';

  @override
  String get profileInviteMember => 'परिवार के सदस्य को आमंत्रित करें';

  @override
  String get profileRemoveMember => 'सदस्य हटाएं';

  @override
  String get profileRelationship => 'रिश्ता';

  @override
  String get profileActive => 'सक्रिय';

  @override
  String get profileCouldNotLoadPayments => 'भुगतान लोड नहीं हो सके।';

  @override
  String get creditAmountToPay => 'भुगतान की जाने वाली राशि';

  @override
  String get creditProceedToPayment => 'भुगतान के लिए आगे बढ़ें';

  @override
  String get creditTxnSuccess => 'आपका लेन-देन सफलतापूर्वक पूरा हुआ।';

  @override
  String get creditTransactionId => 'लेन-देन ID';

  @override
  String get creditNextPaymentDue => 'अगला भुगतान देय';

  @override
  String get creditPayOutstanding => 'बकाया चुकाएं';

  @override
  String get creditHistory => 'इतिहास';

  @override
  String get creditRemaining => 'शेष क्रेडिट';

  @override
  String get creditPurchases => 'खरीदारी';

  @override
  String get creditPaymentsMade => 'किए गए भुगतान';

  @override
  String get creditAppUnderReview => 'आवेदन समीक्षाधीन';

  @override
  String get creditAppNotApproved => 'आवेदन स्वीकृत नहीं';

  @override
  String get creditScoreIncreased => 'VS स्कोर बढ़ा';

  @override
  String get creditGreatBehavior => 'बढ़िया वित्तीय व्यवहार!';

  @override
  String get creditFinancialStatusUpdated => 'वित्तीय स्थिति अपडेट हुई';

  @override
  String get creditTransactionDetails => 'लेन-देन विवरण';

  @override
  String get checkoutViewOrders => 'ऑर्डर देखें';

  @override
  String get checkoutChangeAddress => 'पता बदलें';

  @override
  String get checkoutAmountPayable => 'देय राशि';

  @override
  String get checkoutInclusiveCharges => 'सभी शुल्क सहित';

  @override
  String get checkoutSelectOption => 'विकल्प चुनें';

  @override
  String get checkoutOnlinePayment => 'ऑनलाइन भुगतान';

  @override
  String get checkoutInstantPayment => 'तुरंत भुगतान';

  @override
  String get checkoutPayOnDelivery => 'डिलीवरी पर भुगतान करें';

  @override
  String get checkoutPayOnArrival => 'ऑर्डर आने पर भुगतान करें';

  @override
  String get checkoutBuyNowPayLater => 'अभी खरीदें, बाद में भुगतान करें';

  @override
  String get checkoutUpiCardsNetbanking => 'UPI, कार्ड और नेट बैंकिंग';

  @override
  String get checkoutCreditDebitCard => 'क्रेडिट / डेबिट कार्ड';

  @override
  String get checkoutChooseRepaymentPlan => 'पुनर्भुगतान योजना चुनें';

  @override
  String get checkoutPayoutDate => 'भुगतान तिथि';

  @override
  String get checkoutSecuredByRazorpay => 'भुगतान Razorpay द्वारा सुरक्षित।';

  @override
  String get checkoutOrderConfirmedBody =>
      'धन्यवाद! आपका ऑर्डर पुष्ट हो गया है और तैयार किया जा रहा है।';

  @override
  String get checkoutAgreeTerms =>
      'यह ऑर्डर देकर आप हमारी नियम और शर्तों तथा रिटर्न नीति से सहमत होते हैं।';

  @override
  String get checkoutEnterCoupon => 'कूपन कोड दर्ज करें';

  @override
  String get checkoutCouponValidateFailed => 'कूपन सत्यापित नहीं हो सका';

  @override
  String get kycDetailsTitle => 'KYC विवरण';

  @override
  String get kycVerificationTitle => 'KYC सत्यापन';

  @override
  String get kycVerificationStatus => 'सत्यापन स्थिति';

  @override
  String get kycActionNeeded => 'कार्रवाई आवश्यक';

  @override
  String get kycSubmittedDocs => 'सबमिट किए गए दस्तावेज़';

  @override
  String get kycNoDocuments => 'अभी कोई दस्तावेज़ फ़ाइल में नहीं।';

  @override
  String get kycNeedHelp => 'KYC में मदद चाहिए?';

  @override
  String get kycDataSecured => 'आपका डेटा सुरक्षित है';

  @override
  String get kycChecklist => 'चेकलिस्ट';

  @override
  String kycReason(String reason) {
    return 'कारण: $reason';
  }

  @override
  String get verifyTitle => 'अपनी पहचान सत्यापित करें';

  @override
  String get verifyIdentityDocs => 'पहचान दस्तावेज़';

  @override
  String get verifyIdentityVerification => 'पहचान सत्यापन';

  @override
  String get verifyAadhaar => 'आधार सत्यापन';

  @override
  String get verifyPan => 'पैन सत्यापन';

  @override
  String get verifyFace => 'चेहरा सत्यापन';

  @override
  String get verifySelfie => 'सेल्फी सत्यापन';

  @override
  String get verifyLocation => 'स्थान सत्यापन';

  @override
  String get verifyResidence => 'निवास सत्यापन';

  @override
  String get verifyCreditApp => 'क्रेडिट आवेदन';

  @override
  String get verifyCreditAssessment => 'क्रेडिट मूल्यांकन';

  @override
  String get verifyReviewApp => 'अपने आवेदन की समीक्षा करें';

  @override
  String get verifyPersonalDetails => 'व्यक्तिगत विवरण';

  @override
  String get verifyEmploymentDetails => 'रोज़गार विवरण';

  @override
  String get verifyIncomeInfo => 'आय जानकारी';

  @override
  String get verifyFinancialInfo => 'वित्तीय जानकारी';

  @override
  String get verifyAddressDetails => 'पता विवरण';

  @override
  String get verifyDocuments => 'दस्तावेज़';

  @override
  String get verifyUploadAadhaar => 'आधार अपलोड करें';

  @override
  String get verifyUploadPan => 'पैन फ़ोटो अपलोड करें';

  @override
  String get verifyUploadDocs => 'दस्तावेज़ अपलोड करें';

  @override
  String get verifyUploadContinue => 'अपलोड करें और जारी रखें';

  @override
  String get verifyCapture => 'कैप्चर करें';

  @override
  String get verifyRetake => 'फिर से लें';

  @override
  String get verifyCamera => 'कैमरा';

  @override
  String get verifyGallery => 'गैलरी';

  @override
  String get verifyChooseGallery => 'गैलरी से चुनें';

  @override
  String get verifyStartingCamera => 'कैमरा शुरू हो रहा है…';

  @override
  String get verifyCameraNeeded => 'कैमरा एक्सेस आवश्यक';

  @override
  String get verifyUploaded => 'अपलोड किया गया';

  @override
  String get verifyUploadFailed => 'अपलोड विफल';

  @override
  String get verifySaveDraft => 'ड्राफ्ट सहेजें';

  @override
  String get verifySubmitApp => 'आवेदन सबमिट करें';

  @override
  String get verifyReviewBeforeSubmit =>
      'अनुमोदन के लिए सबमिट करने से पहले प्रत्येक अनुभाग की जांच करें।';

  @override
  String get verifyAppSubmitted => 'आवेदन सबमिट हो गया!';

  @override
  String get verifyAppReceived => 'हमें आपका आवेदन मिल गया';

  @override
  String get verifyTeamVerifying => 'हमारी टीम आपके विवरण सत्यापित कर रही है';

  @override
  String get verifyPending => 'सत्यापन लंबित';

  @override
  String get verifyTrackApp => 'आवेदन ट्रैक करें';

  @override
  String get verifyReapply => 'फिर से आवेदन करें';

  @override
  String get verifyMonthlyIncome => 'मासिक आय';

  @override
  String get verifyOccupation => 'व्यवसाय';

  @override
  String get verifyHouseType => 'घर का प्रकार';

  @override
  String get verifyOwnership => 'स्वामित्व';

  @override
  String get verifyFamilyMembers => 'परिवार के सदस्य';

  @override
  String get verifyRequestedLimit => 'अनुरोधित सीमा';

  @override
  String get verifyRequestedCreditLimit => 'अनुरोधित क्रेडिट सीमा';

  @override
  String get verifyApprovedLimit => 'स्वीकृत क्रेडिट सीमा';

  @override
  String get verifyPotentialLimit => 'संभावित क्रेडिट सीमा';

  @override
  String get verifyAadhaarNumber => '12-अंकों का आधार नंबर';

  @override
  String get verifyPanNumber => 'पैन नंबर';

  @override
  String get verifyAvailableNow => 'अभी उपलब्ध';

  @override
  String get verifyApplicationId => 'आवेदन ID';

  @override
  String get verifySubmittedOn => 'सबमिट किया गया';

  @override
  String get verifyExpectedReview => 'अपेक्षित समीक्षा';

  @override
  String get verifyCurrentStatus => 'वर्तमान स्थिति';

  @override
  String get verifyReason => 'कारण';

  @override
  String get verifyWhyNeed => 'हमें इसकी आवश्यकता क्यों है';

  @override
  String get verifyPhotoRequirements => 'फ़ोटो आवश्यकताएं';

  @override
  String get verifyFaceVisible =>
      'सुनिश्चित करें कि आपका चेहरा स्पष्ट रूप से दिखे।';

  @override
  String get verifyPhotoFormat => 'JPG या PNG, 5 MB तक';

  @override
  String get verifySecureEncrypted => '100% सुरक्षित और एन्क्रिप्टेड';

  @override
  String verifyStepOf(int step, int total) {
    return '$total में से $step चरण';
  }

  @override
  String get supportHowCanWeHelp => 'आज हम आपकी कैसे मदद कर सकते हैं?';

  @override
  String get supportQuickHelp => 'त्वरित सहायता विषय';

  @override
  String get supportSearchFaqs => 'FAQ खोजें';

  @override
  String get supportNewConversation => 'नई बातचीत';

  @override
  String get supportOpenConversation => 'बातचीत खोलें';

  @override
  String get supportStartConversation => 'बातचीत शुरू करें';

  @override
  String get supportNoMessages => 'अभी कोई संदेश नहीं';

  @override
  String get supportNoTickets => 'यहाँ कोई टिकट नहीं';

  @override
  String get supportNoTicketsCategory =>
      'इस श्रेणी में आपके पास अभी कोई टिकट नहीं है।';

  @override
  String get supportTicketDetails => 'टिकट विवरण';

  @override
  String get supportTicketProgress => 'टिकट प्रगति';

  @override
  String get supportIssueCategory => 'समस्या श्रेणी';

  @override
  String get supportIssueDescription => 'समस्या विवरण';

  @override
  String get supportPriorityLevel => 'प्राथमिकता स्तर';

  @override
  String get supportSelectCategory => 'समस्या श्रेणी चुनें';

  @override
  String get supportDescribeIssue => 'कृपया अपनी समस्या विस्तार से बताएं…';

  @override
  String get supportRelatedOrder => 'संबंधित ऑर्डर (वैकल्पिक)';

  @override
  String get supportAttachments => 'अटैचमेंट (वैकल्पिक)';

  @override
  String get supportUploadFile => 'फ़ाइल अपलोड करें';

  @override
  String get supportSubmitTicket => 'टिकट सबमिट करें';

  @override
  String get supportAddReply => 'उत्तर जोड़ें';

  @override
  String get supportTypeMessage => 'अपना संदेश लिखें…';

  @override
  String get supportSendToStart => 'बातचीत शुरू करने के लिए संदेश भेजें।';

  @override
  String get supportCloseTicket => 'टिकट बंद करें';

  @override
  String get supportStillNeedHelp => 'अभी भी मदद चाहिए?';

  @override
  String get supportLiveChat => 'लाइव चैट';

  @override
  String get supportCallSupport => 'सपोर्ट को कॉल करें';

  @override
  String get supportContactInfo => 'संपर्क जानकारी';

  @override
  String get supportRegisteredEmail => 'पंजीकृत ईमेल';

  @override
  String get supportRegisteredMobile => 'पंजीकृत मोबाइल';

  @override
  String get supportResponseTime => 'अनुमानित प्रतिक्रिया समय';

  @override
  String get supportTypicalReply => 'हम आमतौर पर 2 घंटे में उत्तर देते हैं';

  @override
  String get supportCategory => 'श्रेणी';

  @override
  String get supportCreated => 'बनाया गया';

  @override
  String get supportStatusOpen => 'खुला';

  @override
  String get supportStatusClosed => 'बंद';

  @override
  String get supportStatusResolved => 'हल किया गया';

  @override
  String get supportStatusInProgress => 'प्रगति में';

  @override
  String get supportPriorityHigh => 'उच्च प्राथमिकता';

  @override
  String get commonStartShopping => 'खरीदारी शुरू करें';

  @override
  String get commonBuyNow => 'अभी खरीदें';

  @override
  String get commonShareVia => 'इसके माध्यम से शेयर करें';

  @override
  String get offersAndDeals => 'ऑफ़र और डील';

  @override
  String get offersCouponsTitle => 'कूपन और ऑफ़र';

  @override
  String get offersActiveCoupons => 'सक्रिय कूपन';

  @override
  String get offersAvailableCoupons => 'उपलब्ध कूपन';

  @override
  String get offersCashback => 'कैशबैक ऑफ़र';

  @override
  String get offersCombo => 'कॉम्बो ऑफ़र';

  @override
  String get offersFlashDeals => 'फ्लैश डील';

  @override
  String get offersTopDeals => 'टॉप डील';

  @override
  String get offersSpecialDeals => 'विशेष डील';

  @override
  String get offersExpiringSoon => 'जल्द समाप्त हो रहे';

  @override
  String get offersLimitedTime => 'सीमित समय';

  @override
  String get offersSellingFast => 'तेज़ी से बिक रहा';

  @override
  String get offersHowToUse => 'कूपन का उपयोग कैसे करें';

  @override
  String get offersCopy => 'कॉपी करें';

  @override
  String get offersNoCoupons => 'कोई कूपन उपलब्ध नहीं';

  @override
  String get offersNoCouponsYet => 'अभी कोई कूपन नहीं';

  @override
  String get offersNoDeals => 'अभी कोई डील नहीं';

  @override
  String get offersLoadingDeals => 'डील लोड हो रही हैं…';

  @override
  String get offersCouponsAppearHere => 'आपके एकत्र किए कूपन यहाँ दिखेंगे।';

  @override
  String get offersCheckBackSoon => 'नई बचत के लिए जल्द वापस देखें।';

  @override
  String get offersSaveMore => 'हर ऑर्डर पर ज़्यादा बचाएं';

  @override
  String get offersCodeCopied => 'कोड कॉपी किया गया';

  @override
  String get cartBuyOnCredit => 'क्रेडिट पर खरीदें';

  @override
  String get cartPayLaterZeroInterest => 'बिना ब्याज बाद में भुगतान करें।';

  @override
  String get cartPurchaseMode => 'खरीद मोड';

  @override
  String get cartSignInToCheckout => 'चेकआउट के लिए साइन इन करें';

  @override
  String get cartKeepBrowsing => 'ब्राउज़िंग जारी रखें';

  @override
  String get cartItemsNeedAttention =>
      'चेकआउट से पहले कुछ आइटम पर ध्यान देने की आवश्यकता है।';

  @override
  String get wishlistTitle => 'विशलिस्ट';

  @override
  String get wishlistSaved => 'सहेजे गए आइटम';

  @override
  String get wishlistEmpty => 'आपकी विशलिस्ट खाली है';

  @override
  String get wishlistEmptyBody =>
      'बाद के लिए सहेजने हेतु किसी भी उत्पाद पर हार्ट दबाएं।';

  @override
  String get wishlistNoMatch => 'इस फ़िल्टर से कुछ मेल नहीं खाता।';

  @override
  String get wishlistTotalValue => 'विशलिस्ट का कुल मूल्य';

  @override
  String get wishlistPriceDropAlerts => 'मूल्य गिरावट अलर्ट';

  @override
  String get wishlistViewProduct => 'उत्पाद देखें';

  @override
  String get searchFiltersAndSort => 'फ़िल्टर और क्रमबद्ध करें';

  @override
  String get searchPopularity => 'लोकप्रियता';

  @override
  String get searchPriceLowHigh => 'कीमत: कम से अधिक';

  @override
  String get searchRating => 'रेटिंग';

  @override
  String get searchTopRated => 'टॉप रेटेड';

  @override
  String get searchTopRated4Star => 'टॉप रेटेड (4★ और अधिक)';

  @override
  String get settingsAccountSettings => 'खाता सेटिंग्स';

  @override
  String get settingsAppPreferences => 'ऐप प्राथमिकताएं';

  @override
  String get settingsSecuritySettings => 'सुरक्षा सेटिंग्स';

  @override
  String get settingsCreditSettings => 'क्रेडिट सेटिंग्स';

  @override
  String get settingsSupportLegal => 'सहायता और कानूनी';

  @override
  String get settingsEmergencyContacts => 'आपातकालीन संपर्क';

  @override
  String get settingsNotificationPrefs => 'सूचना प्राथमिकताएं';

  @override
  String get settingsLocationPermissions => 'स्थान अनुमतियां';

  @override
  String get settingsChangeMpin => 'MPIN बदलें';

  @override
  String get settingsChangePassword => 'पासवर्ड बदलें';

  @override
  String get settingsManageDevices => 'डिवाइस प्रबंधित करें';

  @override
  String get settingsLoginActivity => 'लॉगिन गतिविधि';

  @override
  String get settingsBiometricLogin => 'बायोमेट्रिक लॉगिन';

  @override
  String get settingsBiometricLock => 'बायोमेट्रिक लॉक';

  @override
  String get settingsAppLock => 'ऐप लॉक';

  @override
  String get settingsSecurityAlerts => 'सुरक्षा अलर्ट';

  @override
  String get settingsNotifyNewLogin => 'नए लॉगिन पर सूचित करें';

  @override
  String get settingsNotifyProfileChanges => 'प्रोफ़ाइल बदलाव पर सूचित करें';

  @override
  String get settingsCreditNotifications => 'क्रेडिट सूचनाएं';

  @override
  String get settingsPaymentReminders => 'भुगतान रिमाइंडर';

  @override
  String get settingsDueDateAlerts => 'देय तिथि अलर्ट';

  @override
  String get settingsStatementNotifications => 'स्टेटमेंट सूचनाएं';

  @override
  String get settingsChannelSettings => 'चैनल सेटिंग्स';

  @override
  String get settingsHelpCenter => 'सहायता केंद्र';

  @override
  String get settingsDeleteAccountQ => 'खाता हटाएं?';

  @override
  String get settingsLogoutQ => 'लॉग आउट करें?';

  @override
  String get settingsAccountDeleted =>
      'खाता हटा दिया गया। आपको साइन आउट किया जा रहा है…';

  @override
  String get settingsEmergencyContact => 'आपातकालीन संपर्क';

  @override
  String get settingsEmergencyContactSaved => 'आपातकालीन संपर्क सहेजा गया।';

  @override
  String get settingsContactMobile => 'संपर्क मोबाइल नंबर';

  @override
  String get settingsCompanyInfo => 'कंपनी जानकारी';

  @override
  String get settingsMissionStatement => 'मिशन वक्तव्य';

  @override
  String get settingsWhatWeOffer => 'हम क्या प्रदान करते हैं';

  @override
  String get settingsGetInTouch => 'संपर्क करें';

  @override
  String get settingsOfficeAddress => 'कार्यालय पता';

  @override
  String get settingsLegalCompliance => 'कानूनी और अनुपालन';

  @override
  String get settingsLicenses => 'लाइसेंस और मान्यताएं';

  @override
  String get settingsWebsite => 'वेबसाइट';

  @override
  String get reviewsTitle => 'रेटिंग और समीक्षाएं';

  @override
  String get reviewsWriteReview => 'समीक्षा लिखें';

  @override
  String get reviewsSubmitReview => 'समीक्षा सबमिट करें';

  @override
  String get reviewsYourRating => 'आपकी रेटिंग';

  @override
  String get reviewsPickRating => 'कृपया एक स्टार रेटिंग चुनें';

  @override
  String get reviewsTitleOptional => 'शीर्षक (वैकल्पिक)';

  @override
  String get reviewsSummarise => 'अपने अनुभव का सारांश दें';

  @override
  String get reviewsYourReview => 'आपकी समीक्षा (वैकल्पिक)';

  @override
  String get reviewsLikeDislike => 'आपको क्या पसंद या नापसंद आया?';

  @override
  String get reviewsThanks => 'आपकी समीक्षा के लिए धन्यवाद!';

  @override
  String get reviewsSubmitFailed =>
      'समीक्षा सबमिट नहीं हो सकी। कृपया फिर से प्रयास करें।';

  @override
  String get referralInviteFriends => 'दोस्तों को आमंत्रित करें';

  @override
  String get referralInviteFriendsNow => 'अभी दोस्तों को आमंत्रित करें';

  @override
  String get referralHowItWorks => 'यह कैसे काम करता है';

  @override
  String get referralHaveCode => 'रेफरल कोड है?';

  @override
  String get referralEnterCode => 'रेफरल कोड दर्ज करें';

  @override
  String get referralCodeApplied => 'रेफरल कोड लागू किया गया';

  @override
  String get referralCodeCopied => 'कोड कॉपी किया गया';

  @override
  String get referralYouEarn => 'आप कमाते हैं';

  @override
  String get referralFirstOrder => 'पहला ऑर्डर';

  @override
  String get referralFriendRegisters => 'दोस्त पंजीकरण करता है';

  @override
  String get referralInviteCopied =>
      'आमंत्रण संदेश कॉपी किया गया — इसे अपने दोस्तों को भेजें';

  @override
  String get notifGroupOrders => 'ऑर्डर सूचनाएं';

  @override
  String get notifGroupPayments => 'भुगतान सूचनाएं';

  @override
  String get notifGroupCredit => 'क्रेडिट सूचनाएं';

  @override
  String get notifGroupPromotional => 'प्रचार सूचनाएं';

  @override
  String get notifOrderConfirmed => 'ऑर्डर पुष्ट';

  @override
  String get notifOrderPacked => 'ऑर्डर पैक किया गया';

  @override
  String get notifOrderOutForDelivery => 'ऑर्डर डिलीवरी के लिए निकला';

  @override
  String get notifOrderDelivered => 'ऑर्डर डिलीवर हो गया';

  @override
  String get notifPaymentSuccess => 'भुगतान सफल';

  @override
  String get notifPaymentFailure => 'भुगतान विफल';

  @override
  String get notifCollectionReminders => 'संग्रह रिमाइंडर';

  @override
  String get notifCreditApproval => 'क्रेडिट स्वीकृति';

  @override
  String get notifCreditLimitUpdates => 'क्रेडिट सीमा अपडेट';

  @override
  String get notifOutstandingDueAlerts => 'बकाया अलर्ट';

  @override
  String get notifVsScoreUpdates => 'VS स्कोर अपडेट';

  @override
  String get notifOffers => 'ऑफ़र';

  @override
  String get notifCoupons => 'कूपन';

  @override
  String get notifCashback => 'कैशबैक';

  @override
  String get notifReferralRewards => 'रेफरल रिवॉर्ड';

  @override
  String get notifPush => 'पुश सूचनाएं';

  @override
  String get notifSms => 'SMS सूचनाएं';

  @override
  String get notifWhatsapp => 'WhatsApp सूचनाएं';

  @override
  String get notifEmail => 'ईमेल सूचनाएं';

  @override
  String get notifLoadError => 'आपकी सूचना सेटिंग्स लोड नहीं हो सकीं।';

  @override
  String get returnsTitle => 'रिटर्न और रिफंड';

  @override
  String get returnStatusRequested => 'अनुरोधित';

  @override
  String get returnStatusApproved => 'स्वीकृत';

  @override
  String get returnStatusRejected => 'अस्वीकृत';

  @override
  String get returnStatusPicked => 'उठा लिया गया';

  @override
  String get returnStatusRefunded => 'रिफंड किया गया';

  @override
  String get returnsEmptyTitle => 'अभी तक कोई रिटर्न नहीं';

  @override
  String get returnsEmptyBody =>
      'आपके द्वारा अनुरोधित रिटर्न और रिफंड यहां दिखाई देंगे।';

  @override
  String returnsOrderNumber(String code) {
    return 'ऑर्डर $code';
  }

  @override
  String get returnsReasonLabel => 'कारण';

  @override
  String get returnsRefundLabel => 'रिफंड';

  @override
  String get returnRequestTitle => 'रिटर्न / रिफंड';

  @override
  String get returnRequestOrderLabel => 'ऑर्डर';

  @override
  String get returnRequestReasonLabel => 'रिटर्न का कारण';

  @override
  String get returnRequestSelectReason => 'एक कारण चुनें';

  @override
  String get returnRequestDescriptionLabel => 'विवरण (वैकल्पिक)';

  @override
  String get returnRequestDescriptionHint =>
      'समस्या के बारे में हमें और बताएं...';

  @override
  String get returnRequestSubmit => 'अनुरोध सबमिट करें';

  @override
  String get returnRequestError =>
      'रिटर्न का अनुरोध नहीं किया जा सका। कृपया पुनः प्रयास करें।';

  @override
  String get returnRequestPhotosLabel => 'वस्तु की तस्वीरें';

  @override
  String get returnRequestPhotosHint =>
      'वस्तु और समस्या को स्पष्ट दिखाने वाली तस्वीरें जोड़ें। हमारा पिकअप पार्टनर इन्हें आपके दरवाज़े पर जाँचेगा।';

  @override
  String get returnRequestAddPhoto => 'तस्वीर जोड़ें';

  @override
  String get returnRequestPhotoRequired =>
      'वस्तु की कम से कम एक तस्वीर जोड़ें।';

  @override
  String returnRequestPhotoLimit(int count) {
    return 'आप अधिकतम $count तस्वीरें जोड़ सकते हैं।';
  }

  @override
  String get returnRequestRemovePhoto => 'तस्वीर हटाएं';

  @override
  String get returnReasonDamaged => 'क्षतिग्रस्त वस्तु';

  @override
  String get returnReasonWrong => 'गलत वस्तु';

  @override
  String get returnReasonQuality => 'गुणवत्ता संबंधी समस्या';

  @override
  String get returnReasonChangedMind => 'मैंने अपना मन बदल लिया';

  @override
  String get returnReasonOther => 'अन्य';

  @override
  String get onboardingSlide1Caption => 'ताज़ा किराना, तेज़ डिलीवरी!';

  @override
  String get onboardingSlide1Title =>
      'ताज़ा किराना आपके दरवाज़े तक पहुंचाया गया';

  @override
  String get onboardingSlide1Body =>
      'सब्ज़ियां, फल, डेयरी उत्पाद, घरेलू ज़रूरी सामान और रोज़मर्रा का किराना तेज़ डिलीवरी के साथ ऑर्डर करें।';

  @override
  String get onboardingSlide2Caption => 'अभी खरीदें, बाद में भुगतान करें';

  @override
  String get onboardingSlide2Title =>
      'VS क्रेडिट से खरीदें, अपनी शर्तों पर भुगतान करें';

  @override
  String get onboardingSlide2Body =>
      'आज जो चाहिए वह खरीदें और बाद में साप्ताहिक या मासिक क्रेडिट के साथ लचीले ढंग से चुकाएं — कोई छिपा हुआ शुल्क नहीं।';

  @override
  String get onboardingSlide3Caption => 'अपना VS स्कोर बढ़ाएं';

  @override
  String get onboardingSlide3Title =>
      'खरीदारी करते हुए अपना क्रेडिट स्कोर बनाएं';

  @override
  String get onboardingSlide3Body =>
      'हर समय पर किया गया भुगतान आपके VS स्कोर को मज़बूत करता है और उच्च क्रेडिट सीमा व बेहतर ऑफ़र अनलॉक करता है।';

  @override
  String get onboardingGetStarted => 'शुरू करें';

  @override
  String get systemUpdateTitle => 'अपडेट आवश्यक है';

  @override
  String get systemUpdateBody =>
      'VS Mart का एक नया संस्करण महत्वपूर्ण सुधारों के साथ उपलब्ध है। जारी रखने के लिए कृपया Play Store से अपडेट करें।';

  @override
  String get systemUpdateNow => 'अभी अपडेट करें';

  @override
  String get systemUpdatedCheckAgain => 'मैंने अपडेट कर लिया — फिर से जांचें';

  @override
  String get systemPlayStoreError =>
      'Play Store नहीं खोला जा सका। अपडेट के लिए कृपया \"VS Mart\" खोजें।';

  @override
  String get systemMaintenanceTitle => 'रखरखाव जारी है';

  @override
  String get systemMaintenanceBody =>
      'हम कुछ सुधार कर रहे हैं और जल्द ही वापस आएंगे। आपके धैर्य के लिए धन्यवाद।';

  @override
  String get systemTryAgain => 'पुनः प्रयास करें';

  @override
  String get systemNoInternetTitle => 'इंटरनेट कनेक्शन नहीं है';

  @override
  String get systemNoInternetBody => 'अपना कनेक्शन जांचें और पुनः प्रयास करें।';

  @override
  String get collectionConfirmTitle => 'भुगतान की पुष्टि करें';

  @override
  String get collectionConfirmLoadError => 'पुष्टि लोड नहीं हो सकी।';

  @override
  String get collectionConfirmNothingTitle => 'पुष्टि करने के लिए कुछ नहीं';

  @override
  String get collectionConfirmNothingBody =>
      'अभी आपके पास कोई लंबित नकद संग्रह नहीं है।';

  @override
  String collectionConfirmCollecting(String name) {
    return '$name संग्रह कर रहे हैं';
  }

  @override
  String get collectionConfirmShareCode => 'यह कोड साझा करें';

  @override
  String collectionConfirmSafetyWarning(String amount) {
    return 'यह कोड केवल तभी साझा करें जब आप $amount नकद में भुगतान कर रहे हों। अन्यथा इसे कभी साझा न करें।';
  }

  @override
  String get collectionConfirmDoneTitle => 'भुगतान की पुष्टि हो गई';

  @override
  String collectionConfirmDoneBody(String name, String amount) {
    return '$name को $amount नकद प्राप्त हो गया है।';
  }

  @override
  String get locationPickerTitle => 'अपना स्थान सेट करें';

  @override
  String get locationConfirm => 'स्थान की पुष्टि करें';

  @override
  String get locationDragHint =>
      'पिन लगाने के लिए मानचित्र को खींचें या टैप करें';

  @override
  String get locationCouldNotGet => 'आपका स्थान प्राप्त नहीं हो सका।';

  @override
  String get locationPermissionNeeded => 'स्थान की अनुमति आवश्यक है।';

  @override
  String get locationSearchSubtitle =>
      'अपना क्षेत्र खोजें, फिर अपने सटीक स्थान पर पिन लगाएं।';

  @override
  String get locationSearchHint => 'क्षेत्र, गली या लैंडमार्क खोजें';

  @override
  String get locationPlaceLoadError =>
      'वह स्थान लोड नहीं हो सका। कोई दूसरा आज़माएं।';

  @override
  String get locationSearchUnavailable =>
      'खोज अभी उपलब्ध नहीं है। अपने वर्तमान स्थान का उपयोग करें, या अपना कनेक्शन जांचकर पुनः प्रयास करें।';

  @override
  String get locationNoMatches => 'कोई मिलान नहीं। कोई दूसरी खोज आज़माएं।';

  @override
  String get paymentReminderTitle => 'भुगतान अनुस्मारक';

  @override
  String get paymentReminderLoadError =>
      'आपकी अनुस्मारक प्राथमिकताएं लोड नहीं हो सकीं।';

  @override
  String get paymentReminderSaved => 'अनुस्मारक प्राथमिकताएं सहेजी गईं।';

  @override
  String get paymentReminderSaveError => 'प्राथमिकताएं सहेजी नहीं जा सकीं।';

  @override
  String get paymentReminderHeadline => 'समय पर बने रहें';

  @override
  String get paymentReminderSubtitle =>
      'देर से लगने वाले शुल्क से बचने और VS Mart के साथ स्वस्थ क्रेडिट स्कोर बनाए रखने के लिए अपने अलर्ट कॉन्फ़िगर करें।';

  @override
  String get paymentReminderEnableTitle => 'अनुस्मारक सक्षम करें';

  @override
  String get paymentReminderEnableSubtitle =>
      'अपनी नियत तारीख से पहले सूचना पाएं';

  @override
  String get paymentReminderWhenTitle => 'हम आपको कब याद दिलाएं?';

  @override
  String get paymentReminderThreeDays => '3 दिन पहले';

  @override
  String get paymentReminderThreeDaysSub => 'आगे की योजना के लिए सर्वोत्तम';

  @override
  String get paymentReminderOneDay => '1 दिन पहले';

  @override
  String get paymentReminderOneDaySub => 'त्वरित अनुस्मारक';

  @override
  String get paymentReminderOnDueDate => 'नियत तारीख पर';

  @override
  String get paymentReminderOnDueDateSub => 'भुगतान की सुबह';

  @override
  String get paymentReminderWeekBefore => 'एक सप्ताह पहले';

  @override
  String get paymentReminderWeekBeforeSub => 'अधिकतम अग्रिम समय';

  @override
  String get paymentReminderHowTitle => 'हम आप तक कैसे पहुंचें?';

  @override
  String get paymentReminderWhatsApp => 'WhatsApp';

  @override
  String get paymentReminderWhatsAppSub => 'तुरंत संदेश डिलीवरी';

  @override
  String get paymentReminderPush => 'पुश सूचना';

  @override
  String get paymentReminderPushSub => 'सीधे आपके VS Mart ऐप पर';

  @override
  String get paymentReminderSms => 'SMS संदेश';

  @override
  String get paymentReminderSmsSub => 'मानक टेक्स्ट संदेश';

  @override
  String get paymentReminderPreferredTime => 'पसंदीदा समय';

  @override
  String get paymentReminderTimeOfDay => 'दिन का समय';

  @override
  String get paymentReminderInfoBanner =>
      'अनुस्मारक सेट करने से आपको देर से लगने वाले शुल्क से बचने में मदद मिलती है और समय पर भुगतान सुनिश्चित करके आपके क्रेडिट स्वास्थ्य पर सकारात्मक प्रभाव पड़ता है।';

  @override
  String get paymentReminderSave => 'प्राथमिकताएं सहेजें';

  @override
  String get supportFaqsHeadline => 'अक्सर पूछे जाने वाले प्रश्नों';

  @override
  String get supportFaqsLoadError =>
      'अक्सर पूछे जाने वाले प्रश्नों (FAQs) को लोड नहीं किया जा सका।';

  @override
  String get supportNoFaqsMatch =>
      'आपकी खोज से मेल खाने वाले कोई FAQ नहीं हैं।';

  @override
  String get supportTeamHereToAssist =>
      'हमारी सहायता टीम आपकी मदद के लिए यहाँ मौजूद है।';

  @override
  String get supportContactSupport => 'समर्थन से संपर्क करें';

  @override
  String get supportAttachLimit => 'आप अधिकतम 3 फाइलें अटैच कर सकते हैं।';

  @override
  String get supportTicketSubmitted => 'टिकट जमा कर दिया गया';

  @override
  String get supportTapToUploadPhotos => 'फ़ोटो अपलोड करने के लिए टैप करें';

  @override
  String get supportMaxFilesSize => 'अधिकतम 3 फ़ाइलें, प्रत्येक 5MB की।';

  @override
  String get supportRespondsWithin24h =>
      'हमारी टीम आमतौर पर 24 घंटों के भीतर जवाब देती है।';

  @override
  String supportTicketCode(String id) {
    return 'टिकट VS-TKT- $id';
  }

  @override
  String supportTicketOpened(String id) {
    return 'टिकट VS-TKT- $id खोला गया';
  }

  @override
  String get supportSearchPrompt =>
      'सहायता, ऑर्डर, भुगतान, क्रेडिट संबंधी समस्याओं आदि के लिए खोजें...';

  @override
  String get supportTicketNotFound => 'टिकट नहीं मिला।';

  @override
  String get supportCloseTicketQ => 'क्या इस टिकट को बंद कर दें?';

  @override
  String get supportCloseTicketBody =>
      'इससे हमारी टीम को पता चल जाता है कि समस्या हल हो गई है और इस पर आगे का काम रोक दिया जाता है। आप बाद में कभी भी नया टिकट बना सकते हैं।';

  @override
  String get supportTicketClosed => 'टिकट बंद।';

  @override
  String settingsCouldNotOpen(String target) {
    return '$target नहीं खोला जा सका।';
  }

  @override
  String get settingsOpenTargetDialer => 'डायलर';

  @override
  String get settingsOpenTargetEmail => 'आपका ईमेल ऐप';

  @override
  String get settingsOpenTargetLink => 'लिंक';

  @override
  String get settingsCompanyDescription =>
      'VS Mart एक अग्रणी हाइब्रिड इकोसिस्टम है जो दैनिक किराना खरीदारी और लचीले वित्तीय ऋण के बीच की खाई को पाटता है, यह सुनिश्चित करते हुए कि परिवारों को जरूरत पड़ने पर आवश्यक वस्तुओं तक निर्बाध पहुंच प्राप्त हो।';

  @override
  String get settingsMissionText =>
      '\"ताज़ा, किफायती किराने का सामान और भरोसेमंद, लचीले ऋण समाधान प्रदान करके समुदायों को सशक्त बनाना, जिससे खरीदारी का एक तनावमुक्त अनुभव प्राप्त हो सके।\"';

  @override
  String get settingsOfferGroceryTitle => 'किराने की खरीदारी';

  @override
  String get settingsOfferGrocerySubtitle => 'ताज़ा दैनिक आवश्यक वस्तुएँ';

  @override
  String get settingsOfferCreditSubtitle => 'लचीले भुगतान विकल्प';

  @override
  String get settingsOfferDeliveryTitle => 'डिलीवरी सेवाएं';

  @override
  String get settingsOfferDeliverySubtitle => 'तेज़ और भरोसेमंद डिलीवरी';

  @override
  String get settingsOfferCollectionsTitle => 'डिजिटल संग्रह';

  @override
  String get settingsOfferCollectionsSubtitle => 'निर्बाध भुगतान';

  @override
  String settingsAllRightsReserved(String app) {
    return '© 2026 $app . सर्वाधिकार सुरक्षित।';
  }

  @override
  String get settingsBiometricLockSubtitle =>
      'VS Mart खोलने के लिए फिंगरप्रिंट/फेस आईडी आवश्यक है';

  @override
  String get settingsNotifyNewLoginSubtitle =>
      'जब आपका खाता साइन इन हो जाए तो सूचना प्राप्त करें';

  @override
  String get settingsNotifyProfileChangesSubtitle =>
      'खाते की जानकारी में बदलाव होने पर मुझे सूचित करें';

  @override
  String get settingsOtpSecurityNote =>
      'आपके VS Mart खाते को हर बार साइन इन करने पर वन-टाइम पासवर्ड ( OTP ) लॉगिन द्वारा सुरक्षित किया जाता है।';

  @override
  String get settingsNoAccountContact =>
      'हमें आपके खाते का संपर्क नहीं मिल पाया। कृपया दोबारा लॉग इन करें।';

  @override
  String get settingsDeletionRequested =>
      'खाता हटाने का अनुरोध किया गया है — हम इस पर कार्रवाई करेंगे और आपका खाता हटा देंगे।';

  @override
  String get billingCreditTab => 'श्रेय';

  @override
  String get billingCreditPendingBody =>
      'हम आपके विवरण की पुष्टि कर रहे हैं। मंज़ूरी मिलते ही आपकी VS Credit लिमिट यहाँ खुल जाएगी — आमतौर पर कुछ ही घंटों में।';

  @override
  String get billingViewStatus => 'स्थिति देखें';

  @override
  String get billingCreditRejectedBody =>
      'आपका पिछला क्रेडिट आवेदन अस्वीकृत हो गया था। आप अपने विवरण की समीक्षा करके दोबारा आवेदन कर सकते हैं।';

  @override
  String get billingUnlockCredit => 'अनलॉक VS Credit';

  @override
  String get billingCreditApplyBody =>
      'VS Credit लाइन के साथ अभी खरीदारी करें और बाद में भुगतान करें। आवेदन करने के लिए त्वरित KYC सत्यापन पूरा करें - इसमें केवल कुछ मिनट लगते हैं।';

  @override
  String get billingApplyForCredit => 'ऋण के लिए आवेदन करें';

  @override
  String get billingCreditEncryptedNote =>
      'आपकी जानकारी एन्क्रिप्टेड है और इसका उपयोग केवल क्रेडिट सत्यापन के लिए किया जाता है।';

  @override
  String get billingBenefitShopPayLater => 'अभी खरीदें, बाद में भुगतान करें';

  @override
  String get billingBenefitFlexiblePlans => 'लचीली साप्ताहिक/मासिक योजनाएँ';

  @override
  String get billingBenefitMemberOffers => 'सदस्यों के लिए विशेष ऑफर';

  @override
  String get billingBenefitBuildScore => 'अपना VS स्कोर बनाएं';

  @override
  String get billingWhyVsCredit => 'VS Credit क्यों?';

  @override
  String billingPercentUsed(int percent) {
    return '$percent % प्रयुक्त';
  }

  @override
  String billingUsedAmount(String amount) {
    return 'उपयोग किया गया: $amount';
  }

  @override
  String billingTotalLimitAmount(String amount) {
    return 'कुल सीमा: $amount';
  }

  @override
  String get billingCollectionRequestRaised =>
      'वसूली का अनुरोध दर्ज कर लिया गया है। एक एजेंट आपसे मिलने आएगा।';

  @override
  String get billingCollectionAddress => 'संग्रह पता';

  @override
  String get billingRegisteredAddress => 'पंजीकृत पता';

  @override
  String get billingAgentVisitAddress =>
      'एजेंट आपके सेव किए गए डिलीवरी पते पर जाएगा।';

  @override
  String get billingCollectionNotesHint =>
      'संग्रहकर्ता एजेंट के लिए कोई निर्देश (वैकल्पिक)';

  @override
  String get billingCollectionAgentInfo =>
      'VS Mart एक कलेक्शन एजेंट नियुक्त किया जाएगा और वह सुरक्षित रूप से भुगतान प्राप्त करने के लिए आपके स्थान पर आएगा। एजेंट की नियुक्ति की पुष्टि होने पर आपको सूचित कर दिया जाएगा।';

  @override
  String get billingAmountToCollect => 'वसूली जाने वाली राशि';

  @override
  String get billingEnterValidAmount => 'एक वैध राशि दर्ज करें';

  @override
  String get billingRequest => 'अनुरोध';

  @override
  String get billingCollectionsAppearHere =>
      'आपके द्वारा अनुरोधित नकद संग्रह पिकअप यहां दिखाई देंगे।';

  @override
  String billingRequestedOn(String date) {
    return 'अनुरोधित $date';
  }

  @override
  String get billingAddress => 'पता';

  @override
  String billingOrderDate(String order, String date) {
    return 'आदेश $order • $date';
  }

  @override
  String get billingInvoiceLoadError => 'इनवॉइस लोड नहीं हो सका';

  @override
  String get billingOutstandingDue => 'बकाया राशि';

  @override
  String get billingDuesLoadError => 'आपकी बकाया राशि लोड नहीं हो सकी।';

  @override
  String billingDueOnDate(String date) {
    return 'नियत $date';
  }

  @override
  String billingOverdueByDays(int days) {
    return '$days दिनों से बकाया है';
  }

  @override
  String billingDueInDays(int days) {
    return 'देय तिथि $days दिन';
  }

  @override
  String get billingTotalOutstandingAmount => 'कुल बकाया राशि';

  @override
  String get billingPayBeforeDueNote =>
      'अच्छा VS स्कोर बनाए रखने और विलंब शुल्क से बचने के लिए नियत तारीख से पहले भुगतान करें।';

  @override
  String get billingPayingTotalAmount => 'कुल राशि का भुगतान';

  @override
  String get billingReceiptDownloaded => 'रसीद डाउनलोड हो गई';

  @override
  String get billingCollectionRequested =>
      'सामान लेने का अनुरोध किया गया है। एक एजेंट नियुक्त किया जाएगा।';

  @override
  String get billingCollectionRequestError =>
      'अनुरोध नहीं भेजा जा सका। पुनः प्रयास करें।';

  @override
  String get billingPaymentFailed => 'भुगतान विफल रहा। कृपया पुनः प्रयास करें।';

  @override
  String get billingProceedToPay => 'चुकाने के लिए कार्रवाई शुरू करो';

  @override
  String get billingOutstandingAmount => 'बकाया राशि';

  @override
  String get billingDebitCreditCard => 'डेबिट / क्रेडिट कार्ड';

  @override
  String get billingNeftImpsTransfer => 'एनईएफटी / आईएमपीएस हस्तांतरण';

  @override
  String get billingRequestAgentPickup => 'एजेंट द्वारा पिकअप का अनुरोध करें';

  @override
  String get billingCreditUpdated => 'क्रेडिट अपडेट किया गया';

  @override
  String get billingStatementDownloaded => 'बयान डाउनलोड किया गया';

  @override
  String get billingNoTransactionsInCycle =>
      'इस चक्र में कोई लेन-देन नहीं हुआ।';

  @override
  String billingPayAmount(String amount) {
    return '$amount का भुगतान करें';
  }

  @override
  String get billingStatusDue => 'देय';

  @override
  String get billingGenerated => 'जनरेट किया गया';

  @override
  String billingBalanceAmount(String amount) {
    return 'शेष राशि $amount';
  }

  @override
  String billingPaymentDue(String date) {
    return 'भुगतान देय $date';
  }

  @override
  String billingAmountDueMin(String amount, String min) {
    return 'देय $amount • $min';
  }

  @override
  String billingAmountDueShort(String amount) {
    return '$amount';
  }

  @override
  String get billingPay => 'वेतन';

  @override
  String get kycDobHelpText => 'जन्म तिथि ( PAN के अनुसार)';

  @override
  String get kycApplyVsCredit => 'VS Credit के लिए आवेदन करें';

  @override
  String get kycStep1VerifyDetails => 'चरण 1/2 · अपने विवरण सत्यापित करें';

  @override
  String get kycDetailsIntro =>
      'अपने PAN पर दी गई जानकारी दर्ज करें। हम आपकी पहचान सत्यापित करने के लिए आपके पंजीकृत नंबर पर आपका CIBIL स्कोर प्राप्त करेंगे।';

  @override
  String get kycNameAsPerPan => 'PAN के अनुसार नाम';

  @override
  String get kycFullNameHint => 'उदाहरण के लिए श्रीनिवासु मगपु';

  @override
  String get kycSelectDob => 'अपनी जन्मतिथि चुनें';

  @override
  String get kycCheckCibil => 'CIBIL जाँच करें';

  @override
  String get kycIdentityVerified => 'पहचान सत्यापित हो गई';

  @override
  String kycCibilScore(String score) {
    return 'CIBIL $score';
  }

  @override
  String get kycStep2Documents => 'चरण 2 का 2 · दस्तावेज़ अपलोड करें';

  @override
  String get kycDocsIntro =>
      'अपने Aadhaar और PAN कार्ड के दोनों तरफ की स्पष्ट तस्वीरें भेजें। एक एजेंट उनकी जांच करेगा।';

  @override
  String get kycAadhaarFront => 'Aadhaar — सामने';

  @override
  String get kycAadhaarBack => 'Aadhaar — वापस';

  @override
  String get kycPanFront => 'PAN — सामने';

  @override
  String get kycPanBack => 'PAN — वापस';

  @override
  String get kycSubmitForVerification => 'सत्यापन के लिए जमा करें';

  @override
  String get kycApplicationSubmitted => 'आवेदन जमा कर दिया गया';

  @override
  String get kycApplicationSubmittedBody =>
      'आपके दस्तावेज़ों की जाँच के लिए एक एजेंट नियुक्त किया जाएगा। मंज़ूरी मिलते ही आपकी VS Credit लिमिट अनलॉक हो जाएगी।';

  @override
  String get kycYourCibilScore => 'आपका CIBIL स्कोर';

  @override
  String get kycTapToChange => 'बदलने के लिए टैप करें';

  @override
  String get kycTapToUpload => 'अपलोड करने के लिए टैप करें';

  @override
  String get kycConsentText =>
      'मैं VS Mart अपनी पहचान सत्यापित करने और अपनी क्रेडिट पात्रता का आकलन करने के लिए क्रेडिट ब्यूरो से मेरा क्रेडिट स्कोर प्राप्त करने के लिए अधिकृत करता हूं।';

  @override
  String get kycLiveSelfie => 'लाइव सेल्फी';

  @override
  String get kycMobileVerified => 'मोबाइल सत्यापित';

  @override
  String get kycAddressAdded => 'पता जोड़ा गया';

  @override
  String get kycStatusLoadError => 'आपकी सत्यापन स्थिति लोड नहीं हो सकी।';

  @override
  String get kycResubmitDocuments => 'दस्तावेज़ पुनः जमा करें';

  @override
  String get kycCompleteToUnlock =>
      'VS Credit लाभों को अनलॉक करने के लिए सत्यापन प्रक्रिया पूरी करें।';

  @override
  String get kycInstantVerification => 'तत्काल सत्यापन';

  @override
  String get kycInstantVerifyBody =>
      'अपने PAN और क्रेडिट स्कोर से एक मिनट में सत्यापित करें';

  @override
  String kycStepsCompleted(int completed, int total) {
    return '$total चरणों में से $completed पूर्ण';
  }

  @override
  String get kycBenefitOnApproval => 'अनुमोदन पर';

  @override
  String get kycBenefitFlexiblePlans => 'लचीली योजनाएँ';

  @override
  String get kycBenefitWeeklyMonthly => 'साप्ताहिक / मासिक';

  @override
  String get kycBenefitExclusiveOffers => 'विशेष ऑफर';

  @override
  String get kycBenefitMemberOnly => 'केवल सदस्यों के लिए';

  @override
  String get kycBenefitBuildCredit => 'क्रेडिट बनाएं';

  @override
  String get kycUnlockBenefits => 'अनलॉक VS Credit लाभ';

  @override
  String get kycSecurityNote =>
      'आपकी जानकारी एन्क्रिप्टेड है और बैंक-स्तरीय सुरक्षा मानकों का पालन करते हुए सुरक्षित रूप से संग्रहीत की जाती है।';

  @override
  String get kycSecurityBannerBody =>
      'आपकी पूरी क्रेडिट लिमिट अनलॉक करने और आरबीआई के नियमों का अनुपालन सुनिश्चित करने के लिए KYC सत्यापन आवश्यक है। हम बैंक-स्तरीय एन्क्रिप्शन का उपयोग करते हैं।';

  @override
  String get kycCaptionVerified =>
      'सभी आवश्यक दस्तावेजों का सफलतापूर्वक सत्यापन हो चुका है।';

  @override
  String get kycCaptionPending =>
      'आपके दस्तावेज़ों की समीक्षा की जा रही है। इसमें आमतौर पर 1-2 दिन लगते हैं।';

  @override
  String get kycCaptionRejected =>
      'कुछ दस्तावेज़ सत्यापित नहीं हो सके। कृपया पुनः जमा करें।';

  @override
  String get kycCaptionNotStarted =>
      'अपनी पूरी क्रेडिट सीमा का लाभ उठाने के लिए अपना KYC पूरा करें।';

  @override
  String kycPercentComplete(int percent) {
    return '$percent पूर्ण प्रतिशत';
  }

  @override
  String get kycStartCardBody =>
      'अपनी पहचान सत्यापित करने के लिए अपना Aadhaar , PAN और एक सेल्फी जमा करें।';

  @override
  String get kycSubmitted => 'प्रस्तुत किया गया';

  @override
  String get commonOr => 'या';

  @override
  String discountPercentOff(int percent) {
    return '$percent % की छूट';
  }

  @override
  String get serviceCheckingArea => 'आपके क्षेत्र की जाँच की जा रही है…';

  @override
  String get serviceConfirmingDelivery =>
      'हम पुष्टि करते हैं कि हम आपके स्थान पर डिलीवरी करते हैं।';

  @override
  String get serviceSetLocationTitle =>
      'जारी रखने के लिए अपना स्थान निर्धारित करें';

  @override
  String get serviceNotInAreaTitle =>
      'आपके क्षेत्र में अभी तक VS Mart उपलब्ध नहीं है।';

  @override
  String get serviceCouldntConfirmBody =>
      'हम आपके स्थान की पुष्टि नहीं कर सके। कृपया ऐसा विकल्प चुनें जिससे हम यह जांच सकें कि क्या VS Mart आपके आस-पास डिलीवरी करता है।';

  @override
  String get serviceExpandingBody =>
      'हम तेजी से विस्तार कर रहे हैं। अपने आस-पास के सेवा-संपन्न क्षेत्र से खरीदारी करने के लिए अपना स्थान बदलें।';

  @override
  String get serviceNotifyWhenHere => 'जब आप यहां पहुंचें तो मुझे सूचित करें';

  @override
  String get serviceLocationOffNote =>
      'आपके फ़ोन में लोकेशन बंद है। इसे चालू करें और फिर से प्रयास करें।';

  @override
  String get serviceOpenLocationSettings => 'स्थान सेटिंग खोलें';

  @override
  String get serviceLocationBlockedNote =>
      'VS Mart के लिए लोकेशन अनुमति ब्लॉक कर दी गई है। कृपया सेटिंग्स में जाकर इसे सक्षम करें और फिर से प्रयास करें।';

  @override
  String get serviceOpenAppSettings => 'ऐप सेटिंग्स खोलें';

  @override
  String get serviceNoGpsFixNote =>
      'जीपीएस लोकेशन नहीं मिल पा रही है। कृपया खिड़की के पास जाएं या बाहर निकलकर दोबारा कोशिश करें, या फिर अपने इलाके को खोजें।';

  @override
  String get serviceDontDeliverThereNote =>
      'हम फिलहाल वहां डिलीवरी नहीं करते हैं। कृपया कोई दूसरा स्थान आजमाएं।';

  @override
  String get serviceChangeLocationBody =>
      'अपने वर्तमान स्थान का उपयोग करें, या अपने क्षेत्र में खोजें और पिन ड्रॉप करें।';

  @override
  String get serviceUseMyCurrentLocation => 'मेरी वर्तमान लोकेशन का उपयोग करें';

  @override
  String get serviceSearchAreaDropPin => 'खोज क्षेत्र और पिन ड्रॉप करें';

  @override
  String get serviceOpenSettings => 'खुली सेटिंग';

  @override
  String get serviceEnterValidPhone => 'एक वैध फ़ोन नंबर दर्ज करें';

  @override
  String get serviceNotifyBody =>
      'अपना नंबर छोड़ दें और जैसे ही VS Mart आपके क्षेत्र में डिलीवरी शुरू करेगा, हम आपको मैसेज भेज देंगे।';

  @override
  String get serviceNameOptional => 'नाम: (वैकल्पिक)';

  @override
  String get servicePhoneHintExample => 'उदाहरण के लिए +9198XXXXXXXX';

  @override
  String get serviceWellNotifyYou => 'हम आपको सूचित करेंगे';

  @override
  String get serviceNotifySuccessBody =>
      'धन्यवाद! हमने आपकी रुचि दर्ज कर ली है और जैसे ही हम आपके आस-पास डिलीवरी शुरू करेंगे, हम आपको संदेश भेज देंगे।';

  @override
  String get wishlistBrowseProducts => 'उत्पाद ब्राउज़ करें';

  @override
  String get wishlistPriceDrop => 'कीमत में गिरावट';

  @override
  String wishlistRemoved(String name) {
    return '$name को विशलिस्ट से हटा दिया गया';
  }

  @override
  String get searchUnderPrice => '₹99 से कम';

  @override
  String searchResultsFound(int count) {
    return '$count परिणाम मिले';
  }

  @override
  String searchNoResultsFor(String query) {
    return 'हमें \" $query \" के लिए कुछ भी नहीं मिला।';
  }

  @override
  String get searchSortPrefix => 'क्रम से लगाना: ';

  @override
  String searchFiltersApplied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count फ़िल्टर लागू',
      one: '1 फ़िल्टर लागू',
    );
    return '$_temp0';
  }

  @override
  String get searchForPrefix => 'निम्न को खोजें ';

  @override
  String reviewsTooLong(int max) {
    return 'आपकी समीक्षा बहुत लंबी है (अधिकतम $max अक्षर)।';
  }

  @override
  String reviewsRatingValue(int rating) {
    return '5 में से $rating सितारे';
  }

  @override
  String reviewsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count समीक्षाएँ',
      one: '1 समीक्षा',
    );
    return '$_temp0';
  }

  @override
  String get reviewsNoneYet => 'अभी तक कोई समीक्षा नहीं, आप पहले बनें';

  @override
  String reviewsRateStars(int star) {
    String _temp0 = intl.Intl.pluralLogic(
      star,
      locale: localeName,
      other: '$star स्टार दें',
      one: '1 स्टार दें',
    );
    return '$_temp0';
  }

  @override
  String get referralCodeHint => 'उदाहरण के लिए VS00042';

  @override
  String get referralTermsApply => 'नियम एवं शर्तें लागू';

  @override
  String referralEarnPerReferral(String amount) {
    return 'प्रत्येक सफल रेफरल पर $amount कमाएँ';
  }

  @override
  String get referralNoneYet =>
      'अभी तक कोई रेफरल नहीं - कमाई शुरू करने के लिए आमंत्रित करें';

  @override
  String referralSuccessfulCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count सफल रेफ़रल',
      one: '1 सफल रेफ़रल',
    );
    return '$_temp0';
  }

  @override
  String get referralYourCode => 'आपका रेफरल कोड';

  @override
  String get referralStepShareBody => 'अपना विशिष्ट लिंक या कोड साझा करें।';

  @override
  String get referralStepRegisterBody =>
      'वे आपके कोड का उपयोग करके साइन अप करते हैं।';

  @override
  String get referralStepOrderBody => 'वे अपना पहला वैध ऑर्डर देते हैं।';

  @override
  String referralStepEarnBody(String amount) {
    return 'आपके वॉलेट में $amount राशि जुड़ जाएगी।';
  }

  @override
  String get offersCouldntLoadDeals => 'डील लोड नहीं हो पा रही हैं।';

  @override
  String get offersCouldntLoadCoupons => 'कूपन लोड नहीं हो सके।';

  @override
  String get offersUpTo60Off => '60% तक की छूट';

  @override
  String get offersOnGroceries => 'किराने का सामान और दैनिक आवश्यक वस्तुओं पर';

  @override
  String get offersTodaysDeals => 'आज के सौदे';

  @override
  String get offersMegaSavings => 'आज की भारी बचत';

  @override
  String get offersUpTo60OffProduce =>
      'ताजे फल और सब्जियों और जरूरी सामानों पर 60% तक की छूट';

  @override
  String get offersFilterFlashSale => 'तेज़ बिक्री';

  @override
  String get offersFilterTopDiscounts => 'सर्वोत्तम छूट';

  @override
  String get offersFilterBuy1Get1 => 'एक खरीदें, दूसरी मुफ़्त पाएं';

  @override
  String get offersOnlyFiveLeft => 'केवल 5 बचे हैं!';

  @override
  String get offersClaimedPercent => '80% ने दावा किया';

  @override
  String offersCodeLabel(String code) {
    return 'कोड: $code';
  }

  @override
  String get loyaltyRedeemPoints => 'अंक भुनाएं';

  @override
  String get loyaltyRewardPoints => 'ईनामी अंक';

  @override
  String get loyaltyPointsAvailable => 'उपलब्ध अंक';

  @override
  String loyaltyLifetimeEarned(String points) {
    return 'जीवन भर अर्जित अंक: $points';
  }

  @override
  String get loyaltyNoActivity => 'अभी तक कोई पॉइंट गतिविधि नहीं हुई है।';

  @override
  String get loyaltyNoActivityBody =>
      'यहां आप अपने पॉइंट्स अर्जित और रिडीम कर सकते हैं और अपना पिछला रिकॉर्ड देख सकते हैं।';

  @override
  String get loyaltyPointsEarned => 'अंक अर्जित किए';

  @override
  String get loyaltyPointsRedeemed => 'अंक भुनाए गए';

  @override
  String get loyaltyPointsExpired => 'पॉइंट्स की समय सीमा समाप्त हो गई है';

  @override
  String get loyaltyPointsAdjustment => 'अंक समायोजन';

  @override
  String get loyaltyEnterValidPoints => 'सही अंकों की संख्या दर्ज करें';

  @override
  String loyaltyOnlyHavePoints(String points) {
    return 'आपके पास केवल $points अंक हैं';
  }

  @override
  String loyaltyPointsAvailableSentence(String points) {
    return 'आपके पास $points अंक उपलब्ध हैं।';
  }

  @override
  String get loyaltyPointsToRedeem => 'रिडीम करने के लिए पॉइंट्स';

  @override
  String get loyaltyPointsHint => 'उदाहरण 100';

  @override
  String get loyaltyRedeem => 'भुनाना';

  @override
  String get notificationsAllCaughtUp => 'आप सभी अपडेट्स से अवगत हैं।';

  @override
  String get notificationsYesterday => 'कल';

  @override
  String homeOrderNumber(String id) {
    return 'आदेश $id';
  }

  @override
  String get homeCouldntLoad => 'लोड नहीं हो सका';

  @override
  String get checkoutCouldNotPlaceOrder =>
      'ऑर्डर नहीं दिया जा सका। कृपया अपनी कार्ट की समीक्षा करें।';

  @override
  String checkoutQty(int count) {
    return 'मात्रा $count';
  }

  @override
  String checkoutCouponAppliedOff(String code, String amount) {
    return '“$code” लागू — $amount की छूट';
  }

  @override
  String checkoutDueDate(String date) {
    return 'नियत $date';
  }

  @override
  String get paymentCouldNotComplete =>
      'भुगतान पूरा नहीं हो सका। कृपया अपना कार्ट और पता जांचें।';

  @override
  String get paymentNotCompleted =>
      'भुगतान पूरा नहीं हुआ। आपका ऑर्डर सुरक्षित है — आप \'मेरे ऑर्डर\' से दोबारा कोशिश कर सकते हैं।';

  @override
  String get cartItemsUnavailableTitle => 'कुछ वस्तुएँ अनुपलब्ध हैं';

  @override
  String get cartItemsUnavailableBody =>
      'ये आइटम आपके स्टोर में स्टॉक से बाहर हो गए हैं। जारी रखने के लिए इन्हें हटा दें।';

  @override
  String get cartRemoveAndContinue => 'हटाएँ और जारी रखें';

  @override
  String get cartReviewCart => 'कार्ट की समीक्षा करें';

  @override
  String get cartSignInBody =>
      'अपना ऑर्डर देने और भुगतान करने के लिए खाता बनाएं या साइन इन करें। आपका कार्ट तैयार है।';

  @override
  String get cartTotalEstimateError =>
      'नवीनतम कुल योग प्राप्त नहीं हो सका — अनुमानित योग दिखाया जा रहा है। पुनः प्रयास करने के लिए टैप करें।';

  @override
  String ordersOrderNumber(Object id) {
    return 'आदेश $id';
  }

  @override
  String get ordersCancelConfirmTitle => 'आदेश रद्द?';

  @override
  String get ordersCancelConfirmBody =>
      'क्या आप यह ऑर्डर रद्द करना चाहते हैं? इसे बदला नहीं जा सकता।';

  @override
  String get ordersKeepOrder => 'व्यवस्था बनाए रखें';

  @override
  String get ordersCancelled => 'आदेश रद्द किया गया';

  @override
  String get ordersTimeline => 'ऑर्डर समयरेखा';

  @override
  String ordersItemQuantity(Object name, int quantity) {
    return '$name × $quantity';
  }

  @override
  String get ordersPayment => 'भुगतान';

  @override
  String get ordersCreditUsed => 'क्रेडिट का उपयोग किया गया';

  @override
  String get ordersOrderPlaced => 'ऑर्डर दिया गया';

  @override
  String get ordersOrderStatus => 'आदेश की स्थिति';

  @override
  String ordersArrivingIn(String eta) {
    return '$eta में पहुंच रहा है';
  }

  @override
  String get ordersOnTheWayHeadline => 'आपका ऑर्डर रास्ते में है';

  @override
  String get ordersWeWillUpdate =>
      'जैसे-जैसे इसमें प्रगति होगी, हम आपको अपडेट देते रहेंगे।';

  @override
  String get ordersContactWhenAssigned =>
      'राइडर असाइन हो जाने के बाद संपर्क दिखाई देता है।';

  @override
  String get ordersDialerError => 'डायलर नहीं खुल सका।';

  @override
  String get ordersDeliveryPartner => 'डिलीवरी पार्टनर';

  @override
  String get ordersRiderOnTheWay => 'रास्ते में';

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
      'आपके डिलीवरी पते पर पिन लोकेशन अंकित होने के बाद लाइव मैप दिखाई देगा।';

  @override
  String ordersMoreItems(int count) {
    return '+ $count और';
  }

  @override
  String ordersItemsAddedToCart(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count आइटम कार्ट में जोड़े गए',
      one: '1 आइटम कार्ट में जोड़ा गया',
    );
    return '$_temp0';
  }

  @override
  String get ordersItemsUnavailable => 'ये आइटम फिलहाल उपलब्ध नहीं हैं।';

  @override
  String get ordersOrderedAt => 'आदेश दिया गया';

  @override
  String get ordersDeliveredAt => 'पर सुपुर्दगी';

  @override
  String get ordersFeedbackThanks => 'प्रतिक्रिया के लिए धन्यवाद!';

  @override
  String get ordersYouRated => 'आपने इस ऑर्डर को रेटिंग दी है';

  @override
  String get ordersHowWasDelivery => 'आपकी डिलीवरी कैसी रही?';

  @override
  String get ordersFeedbackHelps => 'आपका फीडबैक सुधार में मददगार है।';

  @override
  String ordersAgentDelivered(Object name) {
    return '$name ने यह ऑर्डर डिलीवर किया।';
  }

  @override
  String get ordersFeedbackHint => 'कुछ और जोड़ना चाहेंगे? (वैकल्पिक)';

  @override
  String get ordersSendFeedback => 'प्रतिक्रिया भेजें';

  @override
  String ordersStarCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count स्टार',
      one: '1 स्टार',
    );
    return '$_temp0';
  }

  @override
  String get profileLogoutConfirmBody =>
      'अपने खाते तक पहुंचने के लिए आपको दोबारा लॉग इन करना होगा।';

  @override
  String get profileBrowsingAsGuest =>
      'आप अतिथि के रूप में ब्राउज़ कर रहे हैं।';

  @override
  String get profileGuestSignInBody =>
      'ऑर्डर देने, डिलीवरी ट्रैक करने और VS Credit अनलॉक करने के लिए साइन इन करें।';

  @override
  String get profileGuest => 'अतिथि';

  @override
  String profileCreditAmount(Object amount) {
    return '$amount';
  }

  @override
  String profileScoreValue(Object score) {
    return 'स्कोर $score';
  }

  @override
  String profileUsedAmount(Object amount) {
    return 'उपयोग किया गया: $amount';
  }

  @override
  String profileLimitAmount(Object amount) {
    return 'सीमा: $amount';
  }

  @override
  String get profileAddresses => 'पतों';

  @override
  String get profilePayments => 'भुगतान';

  @override
  String get profileSupport => 'सहायता';

  @override
  String get profileMonthlyStatement => 'मासिक विवरण';

  @override
  String get profileOutstandingDue => 'बकाया राशि';

  @override
  String get profileCreditUsage => 'क्रेडिट उपयोग';

  @override
  String get profileVsScoreDetails => 'VS स्कोर विवरण';

  @override
  String get profileNoSavedAddress => 'अभी तक कोई पता सहेजा नहीं गया है।';

  @override
  String get profilePaymentUpi => 'UPI भुगतान';

  @override
  String get profilePaymentCard => 'कार्ड भुगतान';

  @override
  String get profilePaymentBankTransfer => 'बैंक ट्रांसफर';

  @override
  String get profilePaymentCashCollection => 'नकद संग्रह';

  @override
  String get profileViewHistory => 'इतिहास देखें';

  @override
  String get profileKycAadhaar => 'Aadhaar';

  @override
  String get profileKycSelfie => 'सेल्फी';

  @override
  String get profileKycHouse => 'घर सत्यापन';

  @override
  String profileActiveCoupons(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count सक्रिय कूपन',
      one: '1 सक्रिय कूपन',
    );
    return '$_temp0';
  }

  @override
  String get profileLanguageEnglish => 'भाषा अंग्रेजी)';

  @override
  String get profileAboutVsMart => 'VS Mart के बारे में';

  @override
  String get profileCareers => 'करियर';

  @override
  String get profileYou => 'आप';

  @override
  String get profilePrimaryHolder => 'प्राथमिक खाताधारक';

  @override
  String get profileFamilyMember => 'परिवार के सदस्य';

  @override
  String get profileInvitationPending => 'निमंत्रण लंबित है';

  @override
  String get profileHouseholdMember => 'घर का सदस्य';

  @override
  String profileMemberRemoved(Object name) {
    return '$name हटा दिया गया।';
  }

  @override
  String get profileRelationshipHint => 'संबंध (जैसे पति/पत्नी)';

  @override
  String get profileInvite => 'आमंत्रित करना';

  @override
  String profileInviteSent(Object phone) {
    return '$phone पर आमंत्रण भेजा गया।';
  }

  @override
  String get profileHouseholdLoadError =>
      'आपके घरेलू सामान को लोड नहीं किया जा सका।';

  @override
  String get profileFamilySubtitle =>
      'अपने परिवार के लिए साझा क्रेडिट सीमा और खरीदारी प्रोफाइल का प्रबंधन करें।';

  @override
  String get profileSharedLimitUsage => 'साझा सीमा उपयोग';

  @override
  String get profileAddHouseholdMember => 'परिवार के किसी सदस्य को जोड़ें';

  @override
  String get profileAddMemberBody =>
      'अपने परिवार को अपनी VS Mart क्रेडिट लिमिट और खरीदारी की सूची साझा करने के लिए आमंत्रित करें।';

  @override
  String get profileUpdated => 'प्रोफाइल अद्यतन किया गया';

  @override
  String get profilePhotoUpdated => 'प्रोफाइल फोटो अपडेट कर दी गई है।';

  @override
  String get profileNameHint => 'उदाहरण के लिए जेन डो';

  @override
  String get profileEmailHint => 'you@example.com';

  @override
  String get catalogProductNotFound => 'उत्पाद नहीं मिला।';

  @override
  String get catalogRemovedFromWishlist => 'इच्छासूची से हटा दिया गया';

  @override
  String get catalogAddedToWishlist => 'इच्छा सूची में जोड़ना';

  @override
  String get catalogShareSheetError => 'शेयर शीट नहीं खुल सकी।';

  @override
  String get catalogDefaultDescription =>
      'खेतों से सीधे लाए गए और गुणवत्ता के लिए हाथ से चुने गए उत्पाद, अपनी सर्वोत्तम ताजगी के साथ वितरित किए जाते हैं।';

  @override
  String get catalogEligibleForCredit => 'VS Credit के लिए पात्र';

  @override
  String catalogBrowseAllIn(Object name) {
    return '$name में सभी ब्राउज़ करें';
  }

  @override
  String get catalogViewProducts => 'उत्पाद देखें';

  @override
  String get catalogDecreaseQuantity => 'मात्रा घटाएँ';

  @override
  String get catalogIncreaseQuantity => 'मात्रा बढ़ाएँ';

  @override
  String get catalogHandpickedDaily =>
      'विश्वसनीय फार्मों से प्रतिदिन सावधानीपूर्वक चयनित';

  @override
  String get catalogNothingHere => 'यहाँ कुछ भी नहीं है';

  @override
  String get catalogFreshPicksIn => 'ताज़ा चयन';

  @override
  String get catalogHandpickedQuality =>
      'सावधानीपूर्वक चयनित, गुणवत्ता की जांच की गई, शीघ्र वितरण';

  @override
  String get catalogShareLinkCopied => 'शेयर लिंक कॉपी हो गया';

  @override
  String catalogAddedToCart(Object name) {
    return '$name को कार्ट में जोड़ा गया';
  }

  @override
  String catalogPercentOff(Object percent) {
    return '$percent % की छूट';
  }

  @override
  String catalogPriceOnCredit(Object price) {
    return 'VS Credit पर $price';
  }

  @override
  String catalogPriceRange(Object min, Object max) {
    return '₹ $min – ₹ $max';
  }

  @override
  String catalogDiscountOff(Object percent) {
    return '$percent %+ छूट';
  }

  @override
  String get verificationAadhaarInvalid =>
      'वैध 12 अंकों का Aadhaar नंबर दर्ज करें';

  @override
  String get verificationOtpSentAadhaar =>
      'आपके Aadhaar से जुड़े मोबाइल पर OTP भेजा गया है';

  @override
  String get verificationEnterOtpReceived => 'आपको प्राप्त हुआ OTP दर्ज करें';

  @override
  String get verificationAadhaarVerified => 'Aadhaar सत्यापित';

  @override
  String get verificationCouldNotCaptureImage => 'छवि कैप्चर नहीं हो सकी';

  @override
  String get verificationUploadAadhaarBoth =>
      'कृपया Aadhaar आगे और पीछे दोनों तरफ की तस्वीरें अपलोड करें।';

  @override
  String get verificationRequiredForCredit =>
      'VS Credit सक्रिय करने के लिए आवश्यक है।';

  @override
  String get verificationOtpOptionalNote =>
      'वैकल्पिक — इसकी आवश्यकता केवल तभी होगी जब आपको OTP प्राप्त न हो सके।';

  @override
  String get verificationAadhaarFront => 'Aadhaar फ्रंट';

  @override
  String get verificationAadhaarBack => 'Aadhaar वापस';

  @override
  String get verificationCantReceiveOtp =>
      'OTP प्राप्त नहीं हो रहा है? दस्तावेज़ों के साथ जारी रखें';

  @override
  String get verificationWhyAadhaarTitle =>
      'हम Aadhaar सत्यापन का उपयोग निम्न उद्देश्यों के लिए करते हैं:';

  @override
  String get verificationReviewingDetails =>
      'हमारी टीम आपके विवरण की समीक्षा कर रही है। मंज़ूरी मिलने के बाद आपकी क्रेडिट सीमा आपकी प्रोफ़ाइल में दिखाई देगी।';

  @override
  String get verificationCreditReflectionNote =>
      'अनुमोदन के बाद क्रेडिट रिपोर्ट दिखने में 2-4 घंटे लग सकते हैं।';

  @override
  String get verificationCompleteSelections => 'कृपया सभी विकल्प भरें';

  @override
  String get verificationHelpDetermineEligibility =>
      'हमें आपकी क्रेडिट पात्रता निर्धारित करने में मदद करें।';

  @override
  String get verificationHousehold => 'परिवार';

  @override
  String get verificationDraftSaved => 'ड्राफ्ट सहेज लिया गया';

  @override
  String get verificationInitialAssessment =>
      'प्रारंभिक प्रोफाइल मूल्यांकन के आधार पर।';

  @override
  String get verificationUploadAllDocs =>
      'कृपया सभी आवश्यक दस्तावेज़ अपलोड करें';

  @override
  String get verificationWhyDocumentsTitle =>
      'हम आपके दस्तावेज़ों का उपयोग निम्न उद्देश्यों के लिए करते हैं:';

  @override
  String get verificationPanConsentRequired =>
      'कृपया आगे बढ़ने के लिए हमें आपका PAN सत्यापित करने दें।';

  @override
  String get verificationPanVerified => 'PAN सत्यापित';

  @override
  String get verificationPanComplianceNote =>
      'वित्तीय अनुपालन के लिए आपका PAN आवश्यक है।';

  @override
  String get verificationRiskEvaluation => 'जोखिम का आकलन';

  @override
  String get verificationPanConsentText =>
      'मैं VS Mart को KYC के लिए आयकर विभाग से मेरे PAN सत्यापन करने की सहमति देता हूं।';

  @override
  String get verificationVerifyPan => 'PAN सत्यापित करें';

  @override
  String get verificationSubmitYourDetails => 'कृपया अपनी जानकारी जमा करें।';

  @override
  String get verificationResidencePhotoAttached =>
      'निवास स्थान की तस्वीर संलग्न है।';

  @override
  String get verificationCameraGalleryError =>
      'कैमरा/गैलरी तक पहुंच नहीं हो सकी।';

  @override
  String get verificationAddResidencePhoto =>
      'कृपया अपने निवास स्थान की एक तस्वीर जोड़ें।';

  @override
  String get verificationCaptureLocationFirst =>
      'सबमिट करने से पहले अपनी लोकेशन कैप्चर कर लें।';

  @override
  String get verificationResidenceSubmitted =>
      'निवास सत्यापन प्रस्तुत किया गया।';

  @override
  String get verificationResidenceIntro =>
      'कृपया अपने पते की पुष्टि के लिए अपने निवास स्थान की एक स्पष्ट तस्वीर अपलोड करें ताकि प्रक्रिया में तेजी आए और सुरक्षित रूप से सामान पहुंचाया जा सके।';

  @override
  String get verificationSampleApprovedImage => 'नमूना अनुमोदित छवि';

  @override
  String get verificationIdeal => 'आदर्श';

  @override
  String get verificationLatitude => 'अक्षांश';

  @override
  String get verificationLongitude => 'देशान्तर';

  @override
  String get verificationSubmissionFailed =>
      'सबमिशन विफल रहा। कृपया पुनः प्रयास करें।';

  @override
  String get verificationAddress => 'पता';

  @override
  String get verificationSelfie => 'सेल्फी';

  @override
  String get verificationCreditInformation => 'क्रेडिट जानकारी';

  @override
  String get verificationHouse => 'घर';

  @override
  String get verificationCompleteAllSections =>
      'अपना आवेदन जमा करने के लिए सभी अनुभागों को पूरा करें।';

  @override
  String get verificationApplicationSubmitted => 'आवेदन जमा किया गया';

  @override
  String get verificationCreditDecision => 'क्रेडिट पात्रता निर्णय';

  @override
  String verificationApplicationRef(Object id) {
    return 'आवेदन $id';
  }

  @override
  String get verificationNotifyDecision =>
      'जैसे ही कोई निर्णय लिया जाएगा, हम आपको सूचित कर देंगे। इस बीच आप ब्राउज़ करना जारी रख सकते हैं।';

  @override
  String verificationUploading(Object title) {
    return '$title अपलोड हो रहा है…';
  }

  @override
  String get verificationLimitLabel => 'आप LIMIT';

  @override
  String get verificationCaptureFailed => 'कैप्चर विफल';

  @override
  String get verificationSelfieCaptured => 'सेल्फी खींची गई';
}
