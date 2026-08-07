// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Telugu (`te`).
class AppLocalizationsTe extends AppLocalizations {
  AppLocalizationsTe([String locale = 'te']) : super(locale);

  @override
  String get appTagline => 'నిమిషాల్లో కిరాణా';

  @override
  String get commonOk => 'సరే';

  @override
  String get commonCancel => 'రద్దు చేయి';

  @override
  String get commonClose => 'మూసివేయి';

  @override
  String get commonRetry => 'మళ్లీ ప్రయత్నించు';

  @override
  String get commonApply => 'వర్తింపజేయి';

  @override
  String get commonSave => 'సేవ్ చేయి';

  @override
  String get commonContinue => 'కొనసాగించు';

  @override
  String get commonNext => 'తదుపరి';

  @override
  String get commonBack => 'వెనుకకు';

  @override
  String get commonDone => 'పూర్తయింది';

  @override
  String get commonYes => 'అవును';

  @override
  String get commonNo => 'కాదు';

  @override
  String get commonSearch => 'వెతుకు';

  @override
  String get commonSeeAll => 'అన్నీ చూడండి';

  @override
  String get commonLoading => 'లోడ్ అవుతోంది…';

  @override
  String get commonSomethingWentWrong => 'ఏదో తప్పు జరిగింది';

  @override
  String get commonNoInternet => 'ఇంటర్నెట్ కనెక్షన్ లేదు';

  @override
  String get commonTryAgain => 'దయచేసి మళ్లీ ప్రయత్నించండి';

  @override
  String get navHome => 'హోమ్';

  @override
  String get navCategories => 'విభాగాలు';

  @override
  String get navCart => 'కార్ట్';

  @override
  String get navOrders => 'ఆర్డర్లు';

  @override
  String get navAccount => 'ఖాతా';

  @override
  String get navCredit => 'VS క్రెడిట్';

  @override
  String get homeSearchHint =>
      'కిరాణా, బ్రాండ్‌లు మరియు మరిన్నింటి కోసం వెతకండి';

  @override
  String get homeDeliverTo => 'ఇక్కడికి డెలివరీ';

  @override
  String get homeOffersForYou => 'మీ కోసం ఆఫర్లు';

  @override
  String get homeRecommended => 'మీ కోసం సిఫార్సు చేసినవి';

  @override
  String get homePopular => 'మీ దగ్గర ప్రాచుర్యం';

  @override
  String get homeShopByCategory => 'విభాగం వారీగా షాపింగ్';

  @override
  String serviceDeliveringIn(int minutes) {
    return '$minutes నిమిషాల్లో డెలివరీ';
  }

  @override
  String serviceFrom(String store) {
    return '$store నుండి';
  }

  @override
  String get serviceNotAvailableTitle =>
      'మేము ఇంకా మీ ప్రాంతంలో అందుబాటులో లేము';

  @override
  String get serviceNotAvailableBody =>
      'VS Mart ప్రస్తుతం ఈ ప్రాంతానికి డెలివరీ చేయడం లేదు. మీరు ఎక్కడ ఉన్నారో చెప్పండి, మేము ప్రారంభించినప్పుడు మీకు తెలియజేస్తాం.';

  @override
  String get serviceChangeLocation => 'స్థానం మార్చు';

  @override
  String get serviceNotifyMe => 'నాకు తెలియజేయి';

  @override
  String get serviceStoreClosed => 'స్టోర్ ప్రస్తుతం మూసివేయబడింది';

  @override
  String serviceStoreClosedResumesAt(String time) {
    return 'స్టోర్ మూసివేయబడింది. ఆర్డర్లు $time గంటలకు తిరిగి ప్రారంభమవుతాయి.';
  }

  @override
  String get serviceSlotsFull => 'నేటి డెలివరీ స్లాట్‌లు నిండిపోయాయి';

  @override
  String get productAddToCart => 'కార్ట్‌కు జోడించు';

  @override
  String get productAdded => 'జోడించబడింది';

  @override
  String get productOutOfStock => 'స్టాక్ లేదు';

  @override
  String get productInCart => 'కార్ట్‌లో ఉంది';

  @override
  String productSave(String amount) {
    return '$amount ఆదా';
  }

  @override
  String get cartTitle => 'నా కార్ట్';

  @override
  String get cartEmptyTitle => 'మీ కార్ట్ ఖాళీగా ఉంది';

  @override
  String get cartEmptyBody => 'ప్రారంభించడానికి వస్తువులను జోడించండి';

  @override
  String get cartSubtotal => 'సబ్‌టోటల్';

  @override
  String get cartDeliveryFee => 'డెలివరీ ఫీజు';

  @override
  String get cartGst => 'GST';

  @override
  String get cartTotal => 'మొత్తం';

  @override
  String get cartFree => 'ఉచితం';

  @override
  String cartItemsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count వస్తువులు',
      one: '1 వస్తువు',
      zero: 'వస్తువులు లేవు',
    );
    return '$_temp0';
  }

  @override
  String get cartProceedToCheckout => 'చెకౌట్‌కు వెళ్లండి';

  @override
  String get checkoutTitle => 'చెకౌట్';

  @override
  String get checkoutDeliveryAddress => 'డెలివరీ చిరునామా';

  @override
  String get checkoutPaymentMethod => 'చెల్లింపు పద్ధతి';

  @override
  String get checkoutPlaceOrder => 'ఆర్డర్ చేయండి';

  @override
  String get checkoutPayNow => 'ఇప్పుడు చెల్లించండి';

  @override
  String get checkoutCod => 'డెలివరీ సమయంలో నగదు';

  @override
  String get checkoutUpi => 'UPI';

  @override
  String get checkoutCard => 'కార్డ్';

  @override
  String get checkoutVsCredit => 'VS క్రెడిట్';

  @override
  String get checkoutOrderPlacedTitle => 'ఆర్డర్ విజయవంతమైంది!';

  @override
  String checkoutOrderPlacedBody(String code) {
    return 'మీ ఆర్డర్ $code విజయవంతంగా చేయబడింది.';
  }

  @override
  String get creditTitle => 'VS క్రెడిట్';

  @override
  String get creditLimit => 'క్రెడిట్ పరిమితి';

  @override
  String get creditAvailable => 'అందుబాటులో ఉన్న క్రెడిట్';

  @override
  String get creditOutstanding => 'బాకీ';

  @override
  String creditOutstandingAmount(String amount) {
    return 'మీకు $amount బాకీ ఉంది';
  }

  @override
  String creditDueOn(String date) {
    return '$date నాటికి చెల్లించాలి';
  }

  @override
  String get creditRepay => 'తిరిగి చెల్లించు';

  @override
  String get creditRepayNow => 'ఇప్పుడే చెల్లించండి';

  @override
  String get creditPayBill => 'బిల్లు చెల్లించండి';

  @override
  String get creditFrozen => 'మీ క్రెడిట్ తాత్కాలికంగా స్తంభింపజేయబడింది';

  @override
  String get creditCompleteKyc =>
      'VS క్రెడిట్ ఉపయోగించడానికి KYC పూర్తి చేయండి';

  @override
  String get kycTitle => 'ధృవీకరణ';

  @override
  String get kycCompleteTitle => 'మీ KYC పూర్తి చేయండి';

  @override
  String get kycPending => 'ధృవీకరణ ప్రగతిలో ఉంది';

  @override
  String get kycVerified => 'ధృవీకరించబడింది';

  @override
  String get kycRejected => 'ధృవీకరణ తిరస్కరించబడింది';

  @override
  String get kycUploadDocument => 'పత్రాన్ని అప్‌లోడ్ చేయండి';

  @override
  String get kycVerifyIdentity => 'గుర్తింపును ధృవీకరించండి';

  @override
  String get ordersTitle => 'నా ఆర్డర్లు';

  @override
  String get ordersEmpty => 'మీకు ఇంకా ఆర్డర్లు లేవు';

  @override
  String get ordersTrack => 'ఆర్డర్‌ను ట్రాక్ చేయండి';

  @override
  String get reorderSheetTitle => 'వీటిని మీ కార్ట్‌కు జోడించాలా?';

  @override
  String reorderAddAll(int count) {
    return '$count కార్ట్‌కు జోడించు';
  }

  @override
  String get reorderUnavailableHeading => 'ప్రస్తుతం అందుబాటులో లేదు';

  @override
  String get reorderDiscontinued => 'ఇకపై విక్రయించబడదు';

  @override
  String get reorderOutOfStock => 'స్టాక్ లేదు';

  @override
  String get reorderNothingAvailable =>
      'ప్రస్తుతం ఈ వస్తువులేవీ అందుబాటులో లేవు.';

  @override
  String get reorderPricesMayHaveChanged => 'చూపిన ధరలు నేటివి.';

  @override
  String get ordersAmountPaid => 'చెల్లించిన మొత్తం';

  @override
  String get ordersAmountRefunded => 'వాపసు చేయబడింది';

  @override
  String get ordersRefundPending => 'వాపసు ఇంకా జారీ కాలేదు';

  @override
  String get deliveryOtpTitle => 'డెలివరీ OTP';

  @override
  String get deliveryOtpShare => 'ఈ కోడ్‌ను తలుపు వద్ద మీ రైడర్‌కు చెప్పండి';

  @override
  String get profileOrderArriving => 'మీ ఆర్డర్ వస్తోంది';

  @override
  String get profileShowOtp =>
      'ట్రాక్ చేయడానికి మరియు డెలివరీ OTP చూడటానికి నొక్కండి';

  @override
  String get ordersReorder => 'మళ్లీ ఆర్డర్ చేయండి';

  @override
  String get orderStatusPending => 'పెండింగ్';

  @override
  String get orderStatusConfirmed => 'నిర్ధారించబడింది';

  @override
  String get orderStatusPacked => 'ప్యాక్ చేయబడింది';

  @override
  String get orderStatusOutForDelivery => 'డెలివరీకి బయలుదేరింది';

  @override
  String get orderStatusDelivered => 'డెలివరీ అయింది';

  @override
  String get orderStatusCancelled => 'రద్దు చేయబడింది';

  @override
  String get accountTitle => 'ఖాతా';

  @override
  String get accountSettings => 'సెట్టింగ్‌లు';

  @override
  String get accountLanguage => 'భాష';

  @override
  String get accountLogout => 'లాగ్ అవుట్';

  @override
  String get languageTitle => 'భాష';

  @override
  String get languageSelect => 'భాషను ఎంచుకోండి';

  @override
  String get languageCurrent => 'ప్రస్తుత భాష';

  @override
  String get languageApply => 'భాషను వర్తింపజేయి';

  @override
  String get languageUpdated => 'భాష నవీకరించబడింది';

  @override
  String get languagePreview => 'భాష ప్రివ్యూ';

  @override
  String get codeOutsideServiceAreaTitle => 'సేవ అందుబాటులో లేదు';

  @override
  String get codeOutsideServiceAreaBody =>
      'VS Mart ప్రస్తుతం మీ ప్రాంతానికి డెలివరీ చేయడం లేదు.';

  @override
  String get codeStoreClosedTitle => 'స్టోర్ మూసివేయబడింది';

  @override
  String get codeStoreClosedBody =>
      'మీ ప్రాంతానికి సేవలందించే స్టోర్ ప్రస్తుతం ఆర్డర్లు స్వీకరించడం లేదు.';

  @override
  String get codeCapacityReachedTitle => 'డెలివరీ స్లాట్‌లు నిండాయి';

  @override
  String get codeCapacityReachedBody =>
      'మీ ప్రాంతానికి నేటి డెలివరీ సామర్థ్యం నిండిపోయింది. దయచేసి రేపు ప్రయత్నించండి.';

  @override
  String get codeStoreChangedTitle => 'డెలివరీ ప్రాంతం మారింది';

  @override
  String get codeStoreChangedBody =>
      'మీ డెలివరీ చిరునామా వేరే స్టోర్ ప్రాంతానికి మారింది, కాబట్టి మీ కార్ట్ రిఫ్రెష్ చేయబడింది.';

  @override
  String get codeProductUnavailableTitle => 'మీ స్టోర్‌లో అందుబాటులో లేదు';

  @override
  String get codeProductUnavailableBody =>
      'మీ కార్ట్‌లోని కొన్ని వస్తువులు మీ ప్రాంతానికి సేవలందించే స్టోర్‌లో అందుబాటులో లేవు.';

  @override
  String get codeOutOfStockTitle => 'వస్తువు అందుబాటులో లేదు';

  @override
  String get codeOutOfStockBody =>
      'మీ కార్ట్‌లోని ఒకటి లేదా అంతకంటే ఎక్కువ వస్తువులు స్టాక్‌లో లేవు.';

  @override
  String get codeKycRequiredTitle => 'ధృవీకరణ అవసరం';

  @override
  String get codeKycRequiredBody =>
      'VS క్రెడిట్‌తో చెల్లించే ముందు KYC పూర్తి చేయండి.';

  @override
  String get codeCreditDisabledTitle => 'క్రెడిట్ అందుబాటులో లేదు';

  @override
  String get codeCreditDisabledBody =>
      'ఈ ఆర్డర్‌కు VS క్రెడిట్ అందుబాటులో లేదు.';

  @override
  String get codeLimitExceededTitle => 'పరిమితి మించింది';

  @override
  String get codeLimitExceededBody =>
      'ఈ ఆర్డర్ మీ అందుబాటులో ఉన్న క్రెడిట్‌ను మించిపోయింది.';

  @override
  String get codeOverduePaymentTitle => 'చెల్లింపు గడువు దాటింది';

  @override
  String get codeOverduePaymentBody =>
      'కొత్త క్రెడిట్ ఆర్డర్ చేసే ముందు మీ గడువు దాటిన బాకీలను చెల్లించండి.';

  @override
  String get codeSessionExpiredTitle => 'సెషన్ గడువు ముగిసింది';

  @override
  String get codeSessionExpiredBody =>
      'కొనసాగించడానికి దయచేసి మళ్లీ సైన్ ఇన్ చేయండి.';

  @override
  String get commonEdit => 'సవరించు';

  @override
  String get commonDelete => 'తొలగించు';

  @override
  String get commonRemove => 'తీసివేయి';

  @override
  String get commonUpdate => 'నవీకరించు';

  @override
  String get commonConfirm => 'నిర్ధారించు';

  @override
  String get commonSubmit => 'సమర్పించు';

  @override
  String get commonShare => 'షేర్ చేయి';

  @override
  String get commonViewDetails => 'వివరాలు చూడండి';

  @override
  String get commonViewAll => 'అన్నీ చూడండి';

  @override
  String get commonChange => 'మార్చు';

  @override
  String get commonAdd => 'జోడించు';

  @override
  String get commonProceed => 'కొనసాగించు';

  @override
  String get commonSkip => 'దాటవేయి';

  @override
  String get commonRefresh => 'రిఫ్రెష్ చేయి';

  @override
  String get commonClearAll => 'అన్నీ క్లియర్ చేయి';

  @override
  String get commonComingSoon => 'త్వరలో వస్తుంది';

  @override
  String get commonNoData => 'ఇక్కడ ఇంకా ఏమీ లేదు';

  @override
  String get authWelcome => 'VS Mart కు స్వాగతం';

  @override
  String get authEnterPhone => 'మీ మొబైల్ నంబర్ నమోదు చేయండి';

  @override
  String get authPhoneHint => 'మొబైల్ నంబర్';

  @override
  String get authSendOtp => 'OTP పంపండి';

  @override
  String get authEnterOtp => 'OTP నమోదు చేయండి';

  @override
  String authOtpSentTo(String phone) {
    return '$phone కు OTP పంపబడింది';
  }

  @override
  String get authVerify => 'ధృవీకరించు';

  @override
  String get authResendOtp => 'OTP మళ్లీ పంపండి';

  @override
  String authResendIn(int seconds) {
    return '$secondsసె లో మళ్లీ పంపండి';
  }

  @override
  String get authTermsAgree =>
      'కొనసాగించడం ద్వారా మీరు మా నిబంధనలు & గోప్యతా విధానానికి అంగీకరిస్తున్నారు';

  @override
  String get authLoginToContinue => 'కొనసాగించడానికి లాగిన్ చేయండి';

  @override
  String get accountEditProfile => 'ప్రొఫైల్ సవరించు';

  @override
  String get accountMyAddresses => 'నా చిరునామాలు';

  @override
  String get accountPaymentMethods => 'చెల్లింపు పద్ధతులు';

  @override
  String get accountHelpSupport => 'సహాయం & మద్దతు';

  @override
  String get accountAboutUs => 'మా గురించి';

  @override
  String get accountTerms => 'నిబంధనలు & షరతులు';

  @override
  String get accountPrivacy => 'గోప్యతా విధానం';

  @override
  String get accountRateUs => 'మాకు రేటింగ్ ఇవ్వండి';

  @override
  String get accountShareApp => 'యాప్‌ను షేర్ చేయండి';

  @override
  String get accountDeleteAccount => 'ఖాతాను తొలగించండి';

  @override
  String accountVersion(String version) {
    return 'వెర్షన్ $version';
  }

  @override
  String get accountPersonalDetails => 'వ్యక్తిగత వివరాలు';

  @override
  String get accountName => 'పేరు';

  @override
  String get accountEmail => 'ఇమెయిల్';

  @override
  String get accountPhone => 'ఫోన్';

  @override
  String get accountSaveChanges => 'మార్పులను సేవ్ చేయండి';

  @override
  String get orderDetailsTitle => 'ఆర్డర్ వివరాలు';

  @override
  String get orderId => 'ఆర్డర్ ID';

  @override
  String orderPlacedOn(String date) {
    return '$date న చేయబడింది';
  }

  @override
  String get orderItems => 'వస్తువులు';

  @override
  String get orderBillDetails => 'బిల్లు వివరాలు';

  @override
  String get orderDownloadInvoice => 'ఇన్‌వాయిస్ డౌన్‌లోడ్ చేయండి';

  @override
  String get orderNeedHelp => 'సహాయం కావాలా?';

  @override
  String get orderCancel => 'ఆర్డర్ రద్దు చేయండి';

  @override
  String get orderRate => 'ఆర్డర్‌కు రేటింగ్ ఇవ్వండి';

  @override
  String get orderSummary => 'ఆర్డర్ సారాంశం';

  @override
  String get orderDeliveryDetails => 'డెలివరీ వివరాలు';

  @override
  String get orderItemTotal => 'వస్తువుల మొత్తం';

  @override
  String get orderGrandTotal => 'మొత్తం';

  @override
  String orderSaved(String amount) {
    return 'మీరు $amount ఆదా చేసారు';
  }

  @override
  String get creditStatements => 'స్టేట్‌మెంట్‌లు';

  @override
  String get creditPaymentHistory => 'చెల్లింపు చరిత్ర';

  @override
  String get creditRepayment => 'తిరిగి చెల్లింపు';

  @override
  String get creditDueDate => 'గడువు తేదీ';

  @override
  String get creditMinimumDue => 'కనీస బకాయి';

  @override
  String get creditTotalDue => 'మొత్తం బకాయి';

  @override
  String get creditTransactionHistory => 'లావాదేవీల చరిత్ర';

  @override
  String get creditScore => 'VS స్కోర్';

  @override
  String get creditUsed => 'ఉపయోగించినది';

  @override
  String get creditRepaymentPlan => 'తిరిగి చెల్లింపు ప్రణాళిక';

  @override
  String get creditWeekend => 'వారాంతం';

  @override
  String get creditMonthEnd => 'నెలాఖరు';

  @override
  String get creditPayFull => 'పూర్తి మొత్తం చెల్లించండి';

  @override
  String get creditNoDues => 'మీకు ఎలాంటి బకాయిలు లేవు';

  @override
  String get checkoutSelectAddress => 'డెలివరీ చిరునామా ఎంచుకోండి';

  @override
  String get checkoutAddNewAddress => 'కొత్త చిరునామా జోడించండి';

  @override
  String get checkoutApplyCoupon => 'కూపన్ వర్తింపజేయండి';

  @override
  String get checkoutCouponApplied => 'కూపన్ వర్తింపజేయబడింది';

  @override
  String get checkoutBillSummary => 'బిల్లు సారాంశం';

  @override
  String get checkoutItemTotal => 'వస్తువుల మొత్తం';

  @override
  String get checkoutSavings => 'ఆదా';

  @override
  String get checkoutGrandTotal => 'మొత్తం';

  @override
  String get checkoutPaymentOptions => 'చెల్లింపు ఎంపికలు';

  @override
  String get checkoutDeliverySlot => 'డెలివరీ స్లాట్';

  @override
  String get addressAdd => 'చిరునామా జోడించండి';

  @override
  String get addressEdit => 'చిరునామా సవరించండి';

  @override
  String get addressFullName => 'పూర్తి పేరు';

  @override
  String get addressPhone => 'ఫోన్ నంబర్';

  @override
  String get addressPincode => 'పిన్‌కోడ్';

  @override
  String get addressHouseNo => 'ఇల్లు / ఫ్లాట్ నం.';

  @override
  String get addressArea => 'ప్రాంతం / లోకాలిటీ';

  @override
  String get addressLandmark => 'ల్యాండ్‌మార్క్';

  @override
  String get addressCity => 'నగరం';

  @override
  String get addressState => 'రాష్ట్రం';

  @override
  String get addressSave => 'చిరునామా సేవ్ చేయండి';

  @override
  String get addressSetDefault => 'డిఫాల్ట్‌గా సెట్ చేయండి';

  @override
  String get addressType => 'చిరునామా రకం';

  @override
  String get addressHome => 'ఇల్లు';

  @override
  String get addressWork => 'ఆఫీసు';

  @override
  String get addressOther => 'ఇతర';

  @override
  String get addressUseCurrentLocation => 'ప్రస్తుత స్థానాన్ని ఉపయోగించండి';

  @override
  String get addressNone => 'సేవ్ చేసిన చిరునామాలు లేవు';

  @override
  String get notificationsTitle => 'నోటిఫికేషన్‌లు';

  @override
  String get notificationsMarkAllRead => 'అన్నీ చదివినట్లు గుర్తించు';

  @override
  String get notificationsEmpty => 'ఇంకా నోటిఫికేషన్‌లు లేవు';

  @override
  String get notificationsToday => 'ఈరోజు';

  @override
  String get notificationsEarlier => 'ముందు';

  @override
  String get supportTitle => 'సహాయం & మద్దతు';

  @override
  String get supportContactUs => 'మమ్మల్ని సంప్రదించండి';

  @override
  String get supportFaqs => 'తరచుగా అడిగే ప్రశ్నలు';

  @override
  String get supportRaiseTicket => 'టికెట్ సృష్టించండి';

  @override
  String get supportMyTickets => 'నా టికెట్‌లు';

  @override
  String get supportChat => 'మాతో చాట్ చేయండి';

  @override
  String get supportCall => 'మాకు కాల్ చేయండి';

  @override
  String get supportEmail => 'మాకు ఇమెయిల్ చేయండి';

  @override
  String get searchTitle => 'వెతుకు';

  @override
  String get searchHint => 'ఉత్పత్తులను వెతకండి';

  @override
  String get searchNoResults => 'ఫలితాలు కనుగొనబడలేదు';

  @override
  String get searchRecent => 'ఇటీవలి శోధనలు';

  @override
  String get searchPopular => 'ప్రాచుర్యం పొందిన శోధనలు';

  @override
  String searchResultsFor(String query) {
    return '\"$query\" కోసం ఫలితాలు';
  }

  @override
  String get settingsTitle => 'సెట్టింగ్‌లు';

  @override
  String get settingsTheme => 'థీమ్';

  @override
  String get settingsDarkMode => 'డార్క్ మోడ్';

  @override
  String get settingsLightMode => 'లైట్ మోడ్';

  @override
  String get settingsSystemDefault => 'సిస్టమ్ డిఫాల్ట్';

  @override
  String get settingsNotifications => 'నోటిఫికేషన్‌లు';

  @override
  String get settingsPrivacy => 'గోప్యత & భద్రత';

  @override
  String get kycStartCta => 'ధృవీకరణ ప్రారంభించండి';

  @override
  String get kycSubmitForReview => 'సమీక్ష కోసం సమర్పించండి';

  @override
  String get orderStatusDraft => 'డ్రాఫ్ట్';

  @override
  String get orderStatusPlaced => 'ఆర్డర్ చేయబడింది';

  @override
  String get orderStatusReadyForDispatch => 'డిస్పాచ్‌కు సిద్ధం';

  @override
  String get orderStatusRejected => 'తిరస్కరించబడింది';

  @override
  String get orderStatusReturned => 'తిరిగి ఇవ్వబడింది';

  @override
  String get orderStatusPartiallyReturned => 'పాక్షికంగా తిరిగి ఇవ్వబడింది';

  @override
  String get orderStatusFailedDelivery => 'డెలివరీ విఫలమైంది';

  @override
  String get payStatusPaid => 'చెల్లించబడింది';

  @override
  String get payStatusFailed => 'విఫలమైంది';

  @override
  String get payStatusRefunded => 'రీఫండ్ చేయబడింది';

  @override
  String get verifyStatusNotStarted => 'ప్రారంభించలేదు';

  @override
  String get verifyStatusDraft => 'డ్రాఫ్ట్';

  @override
  String get verifyStatusPending => 'పెండింగ్';

  @override
  String get verifyStatusUnderReview => 'సమీక్షలో ఉంది';

  @override
  String get verifyStatusApproved => 'ఆమోదించబడింది';

  @override
  String get verifyStatusRejected => 'తిరస్కరించబడింది';

  @override
  String get kycNotStarted => 'ప్రారంభించలేదు';

  @override
  String get kycDocAadhaar => 'ఆధార్ కార్డ్';

  @override
  String get kycDocPan => 'పాన్ కార్డ్';

  @override
  String get kycDocSelfie => 'సెల్ఫీ / వీడియో KYC';

  @override
  String get kycDocResidence => 'చిరునామా రుజువు';

  @override
  String get catalogAll => 'అన్నీ';

  @override
  String get catalogApplyFilters => 'ఫిల్టర్‌లు వర్తింపజేయండి';

  @override
  String get catalogBrand => 'బ్రాండ్';

  @override
  String get catalogDescription => 'వివరణ';

  @override
  String get catalogFilter => 'ఫిల్టర్';

  @override
  String get catalogFilters => 'ఫిల్టర్‌లు';

  @override
  String get catalogGoToCart => 'కార్ట్‌కు వెళ్లండి';

  @override
  String get catalogInStock => 'స్టాక్‌లో ఉంది';

  @override
  String get catalogInStockOnly => 'స్టాక్‌లో ఉన్నవి మాత్రమే';

  @override
  String get catalogMinDiscount => 'కనీస తగ్గింపు';

  @override
  String get catalogNoCategories => 'విభాగాలు కనుగొనబడలేదు';

  @override
  String get catalogNoProducts => 'ఉత్పత్తులు లేవు';

  @override
  String get catalogNoProductsFound => 'ఉత్పత్తులు కనుగొనబడలేదు';

  @override
  String get catalogPrice => 'ధర';

  @override
  String get catalogProductDetails => 'ఉత్పత్తి వివరాలు';

  @override
  String get catalogProducts => 'ఉత్పత్తులు';

  @override
  String get catalogQuantity => 'పరిమాణం';

  @override
  String get catalogSearchCategories => 'విభాగాలను వెతకండి';

  @override
  String get catalogSelectVariation => 'వేరియంట్ ఎంచుకోండి';

  @override
  String get catalogSort => 'క్రమబద్ధీకరించు';

  @override
  String get catalogSortBy => 'దీని ప్రకారం క్రమబద్ధీకరించు';

  @override
  String get catalogSpecifications => 'వివరణలు';

  @override
  String get catalogNoProductsInCategory => 'ఈ విభాగంలో ఇంకా ఉత్పత్తులు లేవు.';

  @override
  String get catalogAdjustFilters =>
      'మీ ఫిల్టర్‌లు లేదా శోధనను సర్దుబాటు చేయండి.';

  @override
  String get catalogViewCart => 'కార్ట్ చూడండి';

  @override
  String get catalogYouMayAlsoLike => 'మీకు ఇవి కూడా నచ్చవచ్చు';

  @override
  String catalogReviews(int count) {
    return '$count సమీక్షలు';
  }

  @override
  String get catalogBuyNowPayLater =>
      'ఇప్పుడు కొనండి, వడ్డీ లేకుండా తర్వాత చెల్లించండి.';

  @override
  String get homeExploreCategories => 'విభాగాలను అన్వేషించండి';

  @override
  String get homePopularProducts => 'ప్రాచుర్యం పొందిన ఉత్పత్తులు';

  @override
  String get homeRecentlyOrdered => 'ఇటీవల ఆర్డర్ చేసినవి';

  @override
  String get homeShopNow => 'ఇప్పుడే షాపింగ్ చేయండి';

  @override
  String get homeContinueShopping => 'షాపింగ్ కొనసాగించండి';

  @override
  String get homeEnableLocation => 'స్థానాన్ని ప్రారంభించండి';

  @override
  String get homeSpecialSale => 'ప్రత్యేక సేల్ 🔥';

  @override
  String get homeTapToTrack => 'మీ ఆర్డర్‌ను ట్రాక్ చేయడానికి నొక్కండి';

  @override
  String get authCreateAccount => 'ఖాతా సృష్టించండి';

  @override
  String get authVerifyContinue => 'ధృవీకరించి కొనసాగించండి';

  @override
  String get authVerifiedNumber => 'ధృవీకరించబడిన నంబర్';

  @override
  String get authUseDifferentNumber => 'వేరే నంబర్ ఉపయోగించండి';

  @override
  String get authReferralCode => 'రిఫరల్ కోడ్';

  @override
  String get commonOptional => 'ఐచ్ఛికం';

  @override
  String get authAlmostThere => 'దాదాపు పూర్తయింది!';

  @override
  String get authWantCredit => 'ఇప్పుడు కొని తర్వాత చెల్లించాలా?';

  @override
  String get authTermsOfService => 'సేవా నిబంధనలు';

  @override
  String get authGoToHome => 'హోమ్‌కు వెళ్లండి';

  @override
  String get billingPurchase => 'కొనుగోలు';

  @override
  String get billingPenalty => 'జరిమానా';

  @override
  String get billingAdjustment => 'సర్దుబాటు';

  @override
  String get billingRefund => 'రీఫండ్';

  @override
  String get billingCompleted => 'పూర్తయింది';

  @override
  String get billingReversed => 'రద్దు చేయబడింది';

  @override
  String get billingOverdue => 'గడువు దాటింది';

  @override
  String get billingAssigned => 'కేటాయించబడింది';

  @override
  String get billingBankTransfer => 'బ్యాంక్ బదిలీ';

  @override
  String get billingCashCollection => 'నగదు వసూలు';

  @override
  String get billingInvoices => 'ఇన్‌వాయిస్‌లు';

  @override
  String get billingInvoice => 'ఇన్‌వాయిస్';

  @override
  String get billingStatement => 'స్టేట్‌మెంట్';

  @override
  String get billingTransactions => 'లావాదేవీలు';

  @override
  String get billingMakePayment => 'చెల్లింపు చేయండి';

  @override
  String get billingEnterAmount => 'మొత్తాన్ని నమోదు చేయండి';

  @override
  String get billingAmount => 'మొత్తం';

  @override
  String get billingAmountDue => 'చెల్లించవలసిన మొత్తం';

  @override
  String get billingAmountPaid => 'చెల్లించిన మొత్తం';

  @override
  String get billingPayNow => 'ఇప్పుడే చెల్లించండి';

  @override
  String get billingDate => 'తేదీ';

  @override
  String get billingStatus => 'స్థితి';

  @override
  String get billingMethod => 'పద్ధతి';

  @override
  String get billingReference => 'రిఫరెన్స్';

  @override
  String get billingNotes => 'గమనికలు (ఐచ్ఛికం)';

  @override
  String get billingDownloadReceipt => 'రసీదు డౌన్‌లోడ్ చేయండి';

  @override
  String get commonDownload => 'డౌన్‌లోడ్';

  @override
  String get billingViewOrder => 'ఆర్డర్ చూడండి';

  @override
  String get billingViewStatement => 'స్టేట్‌మెంట్ చూడండి';

  @override
  String get billingRequestCollection => 'వసూలు అభ్యర్థించండి';

  @override
  String get billingCollections => 'వసూళ్లు';

  @override
  String get billingCollected => 'వసూలు చేయబడింది';

  @override
  String get billingAgent => 'ఏజెంట్';

  @override
  String get billingPaymentSuccessful => 'చెల్లింపు విజయవంతమైంది';

  @override
  String get billingTotalOutstanding => 'మొత్తం బాకీ';

  @override
  String get billingTotalAmountDue => 'చెల్లించవలసిన మొత్తం';

  @override
  String get billingCurrentBill => 'ప్రస్తుత బిల్లు';

  @override
  String get billingRecentActivity => 'ఇటీవలి కార్యకలాపం';

  @override
  String get billingBreakdown => 'విడివివరాలు';

  @override
  String get billingPrincipal => 'అసలు';

  @override
  String get billingInterest => 'వడ్డీ';

  @override
  String get billingLateFee => 'ఆలస్య రుసుము';

  @override
  String get billingInvoiceNumber => 'ఇన్‌వాయిస్ నంబర్';

  @override
  String get billingInvoiceDate => 'ఇన్‌వాయిస్ తేదీ';

  @override
  String get billingCreditSummary => 'క్రెడిట్ సారాంశం';

  @override
  String get billingBackToDashboard => 'డాష్‌బోర్డ్‌కు తిరిగి';

  @override
  String get billingNoInvoices => 'ఇంకా ఇన్‌వాయిస్‌లు లేవు';

  @override
  String get billingNoPayments => 'ఇంకా చెల్లింపులు లేవు';

  @override
  String get billingNoStatements => 'ఇంకా స్టేట్‌మెంట్‌లు లేవు';

  @override
  String get billingNoCollections => 'వసూలు అభ్యర్థనలు లేవు';

  @override
  String get billingNoTransactions => 'ఇంకా లావాదేవీలు లేవు';

  @override
  String get billingAllCaughtUp => 'అన్నీ పూర్తయ్యాయి';

  @override
  String get billingNoPendingDues => 'మీకు ప్రస్తుతం పెండింగ్ బాకీలు లేవు.';

  @override
  String get billingInvoicesAppearHere =>
      'మీ క్రెడిట్ ఆర్డర్‌ల ఇన్‌వాయిస్‌లు ఇక్కడ కనిపిస్తాయి.';

  @override
  String get billingStatementsAppearHere =>
      'మీ బిల్లింగ్ స్టేట్‌మెంట్‌లు ఇక్కడ కనిపిస్తాయి.';

  @override
  String get billingRepaymentsAppearHere =>
      'మీ తిరిగి చెల్లింపులు ఇక్కడ కనిపిస్తాయి.';

  @override
  String get billingRepaymentRecorded => 'మీ తిరిగి చెల్లింపు నమోదు చేయబడింది.';

  @override
  String get billingSecurePayments => '100% సురక్షిత చెల్లింపులు';

  @override
  String get billingInvoiceNotFound => 'ఇన్‌వాయిస్ కనుగొనబడలేదు';

  @override
  String get billingStatementNotFound => 'స్టేట్‌మెంట్ కనుగొనబడలేదు';

  @override
  String get profileTitle => 'ప్రొఫైల్';

  @override
  String get profileQuickAccess => 'త్వరిత యాక్సెస్';

  @override
  String get profileCreditCenter => 'క్రెడిట్ కేంద్రం';

  @override
  String get profileRecentOrders => 'ఇటీవలి ఆర్డర్లు';

  @override
  String get profileRecentPayments => 'ఇటీవలి చెల్లింపులు';

  @override
  String get profileNoOrders => 'ఇంకా ఆర్డర్లు లేవు';

  @override
  String get profileNotSignedIn => 'సైన్ ఇన్ చేయలేదు';

  @override
  String get profileSignInPrompt =>
      'మీ ప్రొఫైల్‌ను చూడటానికి మరియు సవరించడానికి సైన్ ఇన్ చేయండి.';

  @override
  String get profileSignInCreate => 'సైన్ ఇన్ / ఖాతా సృష్టించండి';

  @override
  String get profilePayDue => 'బాకీ చెల్లించండి';

  @override
  String get profileManageAddresses => 'చిరునామాలను నిర్వహించండి';

  @override
  String get profileMyReturns => 'నా రిటర్న్‌లు';

  @override
  String get profileRewards => 'రివార్డ్‌లు';

  @override
  String get profileReferEarn => 'రిఫర్ & ఎర్న్';

  @override
  String get profileOffersRewards => 'ఆఫర్లు & రివార్డ్‌లు';

  @override
  String get profileViewOffers => 'ఆఫర్లు చూడండి';

  @override
  String get profileFaqHelp => 'FAQ & సహాయం';

  @override
  String get profileGender => 'లింగం';

  @override
  String get profileDob => 'పుట్టిన తేదీ';

  @override
  String get profileChangeNumberNote =>
      'మీ ధృవీకరించిన నంబర్‌ను మార్చడానికి, మద్దతును సంప్రదించండి.';

  @override
  String get profileKycStatus => 'KYC స్థితి';

  @override
  String get profileFamilyInfo => 'కుటుంబ సమాచారం';

  @override
  String get profileHouseholdMembers => 'ఇంటి సభ్యులు';

  @override
  String get profileAddMember => 'సభ్యుడిని జోడించండి';

  @override
  String get profileInviteMember => 'కుటుంబ సభ్యుడిని ఆహ్వానించండి';

  @override
  String get profileRemoveMember => 'సభ్యుడిని తీసివేయండి';

  @override
  String get profileRelationship => 'సంబంధం';

  @override
  String get profileActive => 'యాక్టివ్';

  @override
  String get profileCouldNotLoadPayments => 'చెల్లింపులను లోడ్ చేయలేకపోయాం.';

  @override
  String get creditAmountToPay => 'చెల్లించవలసిన మొత్తం';

  @override
  String get creditProceedToPayment => 'చెల్లింపుకు కొనసాగండి';

  @override
  String get creditTxnSuccess => 'మీ లావాదేవీ విజయవంతంగా పూర్తయింది.';

  @override
  String get creditTransactionId => 'లావాదేవీ ID';

  @override
  String get creditNextPaymentDue => 'తదుపరి చెల్లింపు గడువు';

  @override
  String get creditPayOutstanding => 'బాకీ చెల్లించండి';

  @override
  String get creditHistory => 'చరిత్ర';

  @override
  String get creditRemaining => 'మిగిలిన క్రెడిట్';

  @override
  String get creditPurchases => 'కొనుగోళ్లు';

  @override
  String get creditPaymentsMade => 'చేసిన చెల్లింపులు';

  @override
  String get creditAppUnderReview => 'దరఖాస్తు సమీక్షలో ఉంది';

  @override
  String get creditAppNotApproved => 'దరఖాస్తు ఆమోదించబడలేదు';

  @override
  String get creditScoreIncreased => 'VS స్కోర్ పెరిగింది';

  @override
  String get creditGreatBehavior => 'గొప్ప ఆర్థిక ప్రవర్తన!';

  @override
  String get creditFinancialStatusUpdated => 'ఆర్థిక స్థితి నవీకరించబడింది';

  @override
  String get creditTransactionDetails => 'లావాదేవీ వివరాలు';

  @override
  String get checkoutViewOrders => 'ఆర్డర్లు చూడండి';

  @override
  String get checkoutChangeAddress => 'చిరునామా మార్చండి';

  @override
  String get checkoutAmountPayable => 'చెల్లించవలసిన మొత్తం';

  @override
  String get checkoutInclusiveCharges => 'అన్ని ఛార్జీలతో సహా';

  @override
  String get checkoutSelectOption => 'ఎంపికను ఎంచుకోండి';

  @override
  String get checkoutOnlinePayment => 'ఆన్‌లైన్ చెల్లింపు';

  @override
  String get checkoutInstantPayment => 'తక్షణ చెల్లింపు';

  @override
  String get checkoutPayOnDelivery => 'డెలివరీ సమయంలో చెల్లించండి';

  @override
  String get checkoutPayOnArrival => 'మీ ఆర్డర్ వచ్చినప్పుడు చెల్లించండి';

  @override
  String get checkoutBuyNowPayLater => 'ఇప్పుడు కొనండి, తర్వాత చెల్లించండి';

  @override
  String get checkoutUpiCardsNetbanking => 'UPI, కార్డులు & నెట్ బ్యాంకింగ్';

  @override
  String get checkoutCreditDebitCard => 'క్రెడిట్ / డెబిట్ కార్డ్';

  @override
  String get checkoutChooseRepaymentPlan =>
      'తిరిగి చెల్లింపు ప్రణాళికను ఎంచుకోండి';

  @override
  String get checkoutPayoutDate => 'చెల్లింపు తేదీ';

  @override
  String get checkoutSecuredByRazorpay =>
      'చెల్లింపులు Razorpay ద్వారా సురక్షితం.';

  @override
  String get checkoutOrderConfirmedBody =>
      'ధన్యవాదాలు! మీ ఆర్డర్ నిర్ధారించబడింది మరియు సిద్ధం చేయబడుతోంది.';

  @override
  String get checkoutAgreeTerms =>
      'ఈ ఆర్డర్ చేయడం ద్వారా మీరు మా నిబంధనలు & షరతులు మరియు రిటర్న్ పాలసీకి అంగీకరిస్తున్నారు.';

  @override
  String get checkoutEnterCoupon => 'కూపన్ కోడ్‌ను నమోదు చేయండి';

  @override
  String get checkoutCouponValidateFailed => 'కూపన్‌ను ధృవీకరించలేకపోయాం';

  @override
  String get kycDetailsTitle => 'KYC వివరాలు';

  @override
  String get kycVerificationTitle => 'KYC ధృవీకరణ';

  @override
  String get kycVerificationStatus => 'ధృవీకరణ స్థితి';

  @override
  String get kycActionNeeded => 'చర్య అవసరం';

  @override
  String get kycSubmittedDocs => 'సమర్పించిన పత్రాలు';

  @override
  String get kycNoDocuments => 'ఇంకా ఫైల్‌లో పత్రాలు లేవు.';

  @override
  String get kycNeedHelp => 'KYC తో సహాయం కావాలా?';

  @override
  String get kycDataSecured => 'మీ డేటా సురక్షితం';

  @override
  String get kycChecklist => 'చెక్‌లిస్ట్';

  @override
  String kycReason(String reason) {
    return 'కారణం: $reason';
  }

  @override
  String get verifyTitle => 'మీ గుర్తింపును ధృవీకరించండి';

  @override
  String get verifyIdentityDocs => 'గుర్తింపు పత్రాలు';

  @override
  String get verifyIdentityVerification => 'గుర్తింపు ధృవీకరణ';

  @override
  String get verifyAadhaar => 'ఆధార్ ధృవీకరణ';

  @override
  String get verifyPan => 'పాన్ ధృవీకరణ';

  @override
  String get verifyFace => 'ముఖ ధృవీకరణ';

  @override
  String get verifySelfie => 'సెల్ఫీ ధృవీకరణ';

  @override
  String get verifyLocation => 'స్థాన ధృవీకరణ';

  @override
  String get verifyResidence => 'నివాస ధృవీకరణ';

  @override
  String get verifyCreditApp => 'క్రెడిట్ దరఖాస్తు';

  @override
  String get verifyCreditAssessment => 'క్రెడిట్ మూల్యాంకనం';

  @override
  String get verifyReviewApp => 'మీ దరఖాస్తును సమీక్షించండి';

  @override
  String get verifyPersonalDetails => 'వ్యక్తిగత వివరాలు';

  @override
  String get verifyEmploymentDetails => 'ఉద్యోగ వివరాలు';

  @override
  String get verifyIncomeInfo => 'ఆదాయ సమాచారం';

  @override
  String get verifyFinancialInfo => 'ఆర్థిక సమాచారం';

  @override
  String get verifyAddressDetails => 'చిరునామా వివరాలు';

  @override
  String get verifyDocuments => 'పత్రాలు';

  @override
  String get verifyUploadAadhaar => 'ఆధార్ అప్‌లోడ్ చేయండి';

  @override
  String get verifyUploadPan => 'పాన్ ఫోటో అప్‌లోడ్ చేయండి';

  @override
  String get verifyUploadDocs => 'పత్రాలను అప్‌లోడ్ చేయండి';

  @override
  String get verifyUploadContinue => 'అప్‌లోడ్ చేసి కొనసాగండి';

  @override
  String get verifyCapture => 'క్యాప్చర్';

  @override
  String get verifyRetake => 'మళ్లీ తీయండి';

  @override
  String get verifyCamera => 'కెమెరా';

  @override
  String get verifyGallery => 'గ్యాలరీ';

  @override
  String get verifyChooseGallery => 'గ్యాలరీ నుండి ఎంచుకోండి';

  @override
  String get verifyStartingCamera => 'కెమెరా ప్రారంభమవుతోంది…';

  @override
  String get verifyCameraNeeded => 'కెమెరా యాక్సెస్ అవసరం';

  @override
  String get verifyUploaded => 'అప్‌లోడ్ చేయబడింది';

  @override
  String get verifyUploadFailed => 'అప్‌లోడ్ విఫలమైంది';

  @override
  String get verifySaveDraft => 'డ్రాఫ్ట్ సేవ్ చేయండి';

  @override
  String get verifySubmitApp => 'దరఖాస్తు సమర్పించండి';

  @override
  String get verifyReviewBeforeSubmit =>
      'ఆమోదం కోసం సమర్పించే ముందు ప్రతి విభాగాన్ని సమీక్షించండి.';

  @override
  String get verifyAppSubmitted => 'దరఖాస్తు సమర్పించబడింది!';

  @override
  String get verifyAppReceived => 'మేము మీ దరఖాస్తును అందుకున్నాం';

  @override
  String get verifyTeamVerifying => 'మా బృందం మీ వివరాలను ధృవీకరిస్తోంది';

  @override
  String get verifyPending => 'ధృవీకరణ పెండింగ్‌లో ఉంది';

  @override
  String get verifyTrackApp => 'దరఖాస్తును ట్రాక్ చేయండి';

  @override
  String get verifyReapply => 'మళ్లీ దరఖాస్తు చేయండి';

  @override
  String get verifyMonthlyIncome => 'నెలవారీ ఆదాయం';

  @override
  String get verifyOccupation => 'వృత్తి';

  @override
  String get verifyHouseType => 'ఇంటి రకం';

  @override
  String get verifyOwnership => 'యాజమాన్యం';

  @override
  String get verifyFamilyMembers => 'కుటుంబ సభ్యులు';

  @override
  String get verifyRequestedLimit => 'అభ్యర్థించిన పరిమితి';

  @override
  String get verifyRequestedCreditLimit => 'అభ్యర్థించిన క్రెడిట్ పరిమితి';

  @override
  String get verifyApprovedLimit => 'ఆమోదించిన క్రెడిట్ పరిమితి';

  @override
  String get verifyPotentialLimit => 'సంభావ్య క్రెడిట్ పరిమితి';

  @override
  String get verifyAadhaarNumber => '12-అంకెల ఆధార్ నంబర్';

  @override
  String get verifyPanNumber => 'పాన్ నంబర్';

  @override
  String get verifyAvailableNow => 'ఇప్పుడు అందుబాటులో';

  @override
  String get verifyApplicationId => 'దరఖాస్తు ID';

  @override
  String get verifySubmittedOn => 'సమర్పించిన తేదీ';

  @override
  String get verifyExpectedReview => 'ఆశించిన సమీక్ష';

  @override
  String get verifyCurrentStatus => 'ప్రస్తుత స్థితి';

  @override
  String get verifyReason => 'కారణం';

  @override
  String get verifyWhyNeed => 'మనకు ఇది ఎందుకు అవసరం';

  @override
  String get verifyPhotoRequirements => 'ఫోటో అవసరాలు';

  @override
  String get verifyFaceVisible => 'మీ ముఖం స్పష్టంగా కనిపించేలా చూసుకోండి.';

  @override
  String get verifyPhotoFormat => 'JPG లేదా PNG, 5 MB వరకు';

  @override
  String get verifySecureEncrypted => '100% సురక్షితం & ఎన్‌క్రిప్టెడ్';

  @override
  String verifyStepOf(int step, int total) {
    return '$total లో $stepవ దశ';
  }

  @override
  String get supportHowCanWeHelp => 'ఈరోజు మేము మీకు ఎలా సహాయపడగలం?';

  @override
  String get supportQuickHelp => 'త్వరిత సహాయ అంశాలు';

  @override
  String get supportSearchFaqs => 'FAQ లను వెతకండి';

  @override
  String get supportNewConversation => 'కొత్త సంభాషణ';

  @override
  String get supportOpenConversation => 'సంభాషణ తెరవండి';

  @override
  String get supportStartConversation => 'సంభాషణ ప్రారంభించండి';

  @override
  String get supportNoMessages => 'ఇంకా సందేశాలు లేవు';

  @override
  String get supportNoTickets => 'ఇక్కడ టికెట్‌లు లేవు';

  @override
  String get supportNoTicketsCategory => 'ఈ విభాగంలో మీకు ఇంకా టికెట్‌లు లేవు.';

  @override
  String get supportTicketDetails => 'టికెట్ వివరాలు';

  @override
  String get supportTicketProgress => 'టికెట్ పురోగతి';

  @override
  String get supportIssueCategory => 'సమస్య విభాగం';

  @override
  String get supportIssueDescription => 'సమస్య వివరణ';

  @override
  String get supportPriorityLevel => 'ప్రాధాన్యత స్థాయి';

  @override
  String get supportSelectCategory => 'సమస్య విభాగాన్ని ఎంచుకోండి';

  @override
  String get supportDescribeIssue => 'దయచేసి మీ సమస్యను వివరంగా వివరించండి…';

  @override
  String get supportRelatedOrder => 'సంబంధిత ఆర్డర్ (ఐచ్ఛికం)';

  @override
  String get supportAttachments => 'జోడింపులు (ఐచ్ఛికం)';

  @override
  String get supportUploadFile => 'ఫైల్ అప్‌లోడ్ చేయండి';

  @override
  String get supportSubmitTicket => 'టికెట్ సమర్పించండి';

  @override
  String get supportAddReply => 'ప్రత్యుత్తరం జోడించండి';

  @override
  String get supportTypeMessage => 'మీ సందేశాన్ని టైప్ చేయండి…';

  @override
  String get supportSendToStart => 'సంభాషణ ప్రారంభించడానికి సందేశం పంపండి.';

  @override
  String get supportCloseTicket => 'టికెట్ మూసివేయండి';

  @override
  String get supportStillNeedHelp => 'ఇంకా సహాయం కావాలా?';

  @override
  String get supportLiveChat => 'లైవ్ చాట్';

  @override
  String get supportCallSupport => 'సపోర్ట్‌కు కాల్ చేయండి';

  @override
  String get supportContactInfo => 'సంప్రదింపు సమాచారం';

  @override
  String get supportRegisteredEmail => 'నమోదిత ఇమెయిల్';

  @override
  String get supportRegisteredMobile => 'నమోదిత మొబైల్';

  @override
  String get supportResponseTime => 'అంచనా ప్రతిస్పందన సమయం';

  @override
  String get supportTypicalReply =>
      'మేము సాధారణంగా 2 గంటల్లో ప్రత్యుత్తరం ఇస్తాం';

  @override
  String get supportCategory => 'విభాగం';

  @override
  String get supportCreated => 'సృష్టించబడింది';

  @override
  String get supportStatusOpen => 'తెరిచి ఉంది';

  @override
  String get supportStatusClosed => 'మూసివేయబడింది';

  @override
  String get supportStatusResolved => 'పరిష్కరించబడింది';

  @override
  String get supportStatusInProgress => 'ప్రగతిలో ఉంది';

  @override
  String get supportPriorityHigh => 'అధిక ప్రాధాన్యత';

  @override
  String get commonStartShopping => 'షాపింగ్ ప్రారంభించండి';

  @override
  String get commonBuyNow => 'ఇప్పుడే కొనండి';

  @override
  String get commonShareVia => 'దీని ద్వారా షేర్ చేయండి';

  @override
  String get offersAndDeals => 'ఆఫర్లు & డీల్‌లు';

  @override
  String get offersCouponsTitle => 'కూపన్‌లు & ఆఫర్లు';

  @override
  String get offersActiveCoupons => 'యాక్టివ్ కూపన్‌లు';

  @override
  String get offersAvailableCoupons => 'అందుబాటులో ఉన్న కూపన్‌లు';

  @override
  String get offersCashback => 'క్యాష్‌బ్యాక్ ఆఫర్లు';

  @override
  String get offersCombo => 'కాంబో ఆఫర్లు';

  @override
  String get offersFlashDeals => 'ఫ్లాష్ డీల్‌లు';

  @override
  String get offersTopDeals => 'టాప్ డీల్‌లు';

  @override
  String get offersSpecialDeals => 'ప్రత్యేక డీల్‌లు';

  @override
  String get offersExpiringSoon => 'త్వరలో గడువు ముగుస్తుంది';

  @override
  String get offersLimitedTime => 'పరిమిత సమయం';

  @override
  String get offersSellingFast => 'వేగంగా అమ్ముడవుతోంది';

  @override
  String get offersHowToUse => 'కూపన్‌ను ఎలా ఉపయోగించాలి';

  @override
  String get offersCopy => 'కాపీ చేయండి';

  @override
  String get offersNoCoupons => 'కూపన్‌లు అందుబాటులో లేవు';

  @override
  String get offersNoCouponsYet => 'ఇంకా కూపన్‌లు లేవు';

  @override
  String get offersNoDeals => 'ప్రస్తుతం డీల్‌లు లేవు';

  @override
  String get offersLoadingDeals => 'డీల్‌లు లోడ్ అవుతున్నాయి…';

  @override
  String get offersCouponsAppearHere =>
      'మీరు సేకరించిన కూపన్‌లు ఇక్కడ కనిపిస్తాయి.';

  @override
  String get offersCheckBackSoon => 'కొత్త పొదుపుల కోసం త్వరలో మళ్లీ చూడండి.';

  @override
  String get offersSaveMore => 'ప్రతి ఆర్డర్‌పై మరింత ఆదా చేయండి';

  @override
  String get offersCodeCopied => 'కోడ్ కాపీ చేయబడింది';

  @override
  String get cartBuyOnCredit => 'క్రెడిట్‌తో కొనండి';

  @override
  String get cartPayLaterZeroInterest => 'వడ్డీ లేకుండా తర్వాత చెల్లించండి.';

  @override
  String get cartPurchaseMode => 'కొనుగోలు మోడ్';

  @override
  String get cartSignInToCheckout => 'చెకౌట్ చేయడానికి సైన్ ఇన్ చేయండి';

  @override
  String get cartKeepBrowsing => 'బ్రౌజింగ్ కొనసాగించండి';

  @override
  String get cartItemsNeedAttention =>
      'చెకౌట్‌కు ముందు కొన్ని వస్తువులకు శ్రద్ధ అవసరం.';

  @override
  String get wishlistTitle => 'విష్‌లిస్ట్';

  @override
  String get wishlistSaved => 'సేవ్ చేసిన వస్తువులు';

  @override
  String get wishlistEmpty => 'మీ విష్‌లిస్ట్ ఖాళీగా ఉంది';

  @override
  String get wishlistEmptyBody =>
      'తర్వాత కోసం సేవ్ చేయడానికి ఏదైనా ఉత్పత్తిపై హార్ట్‌ను నొక్కండి.';

  @override
  String get wishlistNoMatch => 'ఈ ఫిల్టర్‌కు ఏదీ సరిపోలడం లేదు.';

  @override
  String get wishlistTotalValue => 'విష్‌లిస్ట్ మొత్తం విలువ';

  @override
  String get wishlistPriceDropAlerts => 'ధర తగ్గింపు హెచ్చరికలు';

  @override
  String get wishlistViewProduct => 'ఉత్పత్తిని చూడండి';

  @override
  String get searchFiltersAndSort => 'ఫిల్టర్‌లు & క్రమబద్ధీకరణ';

  @override
  String get searchPopularity => 'ప్రాచుర్యం';

  @override
  String get searchPriceLowHigh => 'ధర: తక్కువ నుండి ఎక్కువ';

  @override
  String get searchRating => 'రేటింగ్';

  @override
  String get searchTopRated => 'టాప్ రేటెడ్';

  @override
  String get searchTopRated4Star => 'టాప్ రేటెడ్ (4★ మరియు అంతకంటే ఎక్కువ)';

  @override
  String get settingsAccountSettings => 'ఖాతా సెట్టింగ్‌లు';

  @override
  String get settingsAppPreferences => 'యాప్ ప్రాధాన్యతలు';

  @override
  String get settingsSecuritySettings => 'భద్రతా సెట్టింగ్‌లు';

  @override
  String get settingsCreditSettings => 'క్రెడిట్ సెట్టింగ్‌లు';

  @override
  String get settingsSupportLegal => 'మద్దతు & చట్టపరమైనది';

  @override
  String get settingsEmergencyContacts => 'అత్యవసర సంప్రదింపులు';

  @override
  String get settingsNotificationPrefs => 'నోటిఫికేషన్ ప్రాధాన్యతలు';

  @override
  String get settingsLocationPermissions => 'స్థాన అనుమతులు';

  @override
  String get settingsChangeMpin => 'MPIN మార్చండి';

  @override
  String get settingsChangePassword => 'పాస్‌వర్డ్ మార్చండి';

  @override
  String get settingsManageDevices => 'పరికరాలను నిర్వహించండి';

  @override
  String get settingsLoginActivity => 'లాగిన్ కార్యకలాపం';

  @override
  String get settingsBiometricLogin => 'బయోమెట్రిక్ లాగిన్';

  @override
  String get settingsBiometricLock => 'బయోమెట్రిక్ లాక్';

  @override
  String get settingsAppLock => 'యాప్ లాక్';

  @override
  String get settingsSecurityAlerts => 'భద్రతా హెచ్చరికలు';

  @override
  String get settingsNotifyNewLogin => 'కొత్త లాగిన్‌పై తెలియజేయండి';

  @override
  String get settingsNotifyProfileChanges => 'ప్రొఫైల్ మార్పులపై తెలియజేయండి';

  @override
  String get settingsCreditNotifications => 'క్రెడిట్ నోటిఫికేషన్‌లు';

  @override
  String get settingsPaymentReminders => 'చెల్లింపు రిమైండర్‌లు';

  @override
  String get settingsDueDateAlerts => 'గడువు తేదీ హెచ్చరికలు';

  @override
  String get settingsStatementNotifications => 'స్టేట్‌మెంట్ నోటిఫికేషన్‌లు';

  @override
  String get settingsChannelSettings => 'ఛానెల్ సెట్టింగ్‌లు';

  @override
  String get settingsHelpCenter => 'సహాయ కేంద్రం';

  @override
  String get settingsDeleteAccountQ => 'ఖాతాను తొలగించాలా?';

  @override
  String get settingsLogoutQ => 'లాగ్ అవుట్ చేయాలా?';

  @override
  String get settingsAccountDeleted =>
      'ఖాతా తొలగించబడింది. మిమ్మల్ని సైన్ అవుట్ చేస్తున్నాం…';

  @override
  String get settingsEmergencyContact => 'అత్యవసర సంప్రదింపు';

  @override
  String get settingsEmergencyContactSaved =>
      'అత్యవసర సంప్రదింపు సేవ్ చేయబడింది.';

  @override
  String get settingsContactMobile => 'సంప్రదింపు మొబైల్ నంబర్';

  @override
  String get settingsCompanyInfo => 'కంపెనీ సమాచారం';

  @override
  String get settingsMissionStatement => 'లక్ష్య ప్రకటన';

  @override
  String get settingsWhatWeOffer => 'మేము అందించేవి';

  @override
  String get settingsGetInTouch => 'సంప్రదించండి';

  @override
  String get settingsOfficeAddress => 'కార్యాలయ చిరునామా';

  @override
  String get settingsLegalCompliance => 'చట్టపరమైన & సమ్మతి';

  @override
  String get settingsLicenses => 'లైసెన్స్‌లు & గుర్తింపులు';

  @override
  String get settingsWebsite => 'వెబ్‌సైట్';

  @override
  String get reviewsTitle => 'రేటింగ్‌లు & సమీక్షలు';

  @override
  String get reviewsWriteReview => 'సమీక్ష రాయండి';

  @override
  String get reviewsSubmitReview => 'సమీక్షను సమర్పించండి';

  @override
  String get reviewsYourRating => 'మీ రేటింగ్';

  @override
  String get reviewsPickRating => 'దయచేసి ఒక స్టార్ రేటింగ్ ఎంచుకోండి';

  @override
  String get reviewsTitleOptional => 'శీర్షిక (ఐచ్ఛికం)';

  @override
  String get reviewsSummarise => 'మీ అనుభవాన్ని సంగ్రహించండి';

  @override
  String get reviewsYourReview => 'మీ సమీక్ష (ఐచ్ఛికం)';

  @override
  String get reviewsLikeDislike => 'మీకు ఏది నచ్చింది లేదా నచ్చలేదు?';

  @override
  String get reviewsThanks => 'మీ సమీక్షకు ధన్యవాదాలు!';

  @override
  String get reviewsSubmitFailed =>
      'సమీక్షను సమర్పించలేకపోయాం. దయచేసి మళ్లీ ప్రయత్నించండి.';

  @override
  String get referralInviteFriends => 'స్నేహితులను ఆహ్వానించండి';

  @override
  String get referralInviteFriendsNow => 'ఇప్పుడే స్నేహితులను ఆహ్వానించండి';

  @override
  String get referralHowItWorks => 'ఇది ఎలా పనిచేస్తుంది';

  @override
  String get referralHaveCode => 'రిఫరల్ కోడ్ ఉందా?';

  @override
  String get referralEnterCode => 'రిఫరల్ కోడ్‌ను నమోదు చేయండి';

  @override
  String get referralCodeApplied => 'రిఫరల్ కోడ్ వర్తింపజేయబడింది';

  @override
  String get referralCodeCopied => 'కోడ్ కాపీ చేయబడింది';

  @override
  String get referralYouEarn => 'మీరు సంపాదిస్తారు';

  @override
  String get referralFirstOrder => 'మొదటి ఆర్డర్';

  @override
  String get referralFriendRegisters => 'స్నేహితుడు నమోదు చేసుకుంటారు';

  @override
  String get referralInviteCopied =>
      'ఆహ్వాన సందేశం కాపీ చేయబడింది — దీన్ని మీ స్నేహితులకు పంపండి';

  @override
  String get notifGroupOrders => 'ఆర్డర్ నోటిఫికేషన్‌లు';

  @override
  String get notifGroupPayments => 'చెల్లింపు నోటిఫికేషన్‌లు';

  @override
  String get notifGroupCredit => 'క్రెడిట్ నోటిఫికేషన్‌లు';

  @override
  String get notifGroupPromotional => 'ప్రచార నోటిఫికేషన్‌లు';

  @override
  String get notifOrderConfirmed => 'ఆర్డర్ నిర్ధారించబడింది';

  @override
  String get notifOrderPacked => 'ఆర్డర్ ప్యాక్ చేయబడింది';

  @override
  String get notifOrderOutForDelivery => 'ఆర్డర్ డెలివరీకి బయలుదేరింది';

  @override
  String get notifOrderDelivered => 'ఆర్డర్ డెలివరీ అయింది';

  @override
  String get notifPaymentSuccess => 'చెల్లింపు విజయవంతం';

  @override
  String get notifPaymentFailure => 'చెల్లింపు విఫలం';

  @override
  String get notifCollectionReminders => 'వసూలు రిమైండర్‌లు';

  @override
  String get notifCreditApproval => 'క్రెడిట్ ఆమోదం';

  @override
  String get notifCreditLimitUpdates => 'క్రెడిట్ పరిమితి నవీకరణలు';

  @override
  String get notifOutstandingDueAlerts => 'బాకీ హెచ్చరికలు';

  @override
  String get notifVsScoreUpdates => 'VS స్కోర్ నవీకరణలు';

  @override
  String get notifOffers => 'ఆఫర్లు';

  @override
  String get notifCoupons => 'కూపన్‌లు';

  @override
  String get notifCashback => 'క్యాష్‌బ్యాక్';

  @override
  String get notifReferralRewards => 'రిఫరల్ రివార్డ్‌లు';

  @override
  String get notifPush => 'పుష్ నోటిఫికేషన్‌లు';

  @override
  String get notifSms => 'SMS నోటిఫికేషన్‌లు';

  @override
  String get notifWhatsapp => 'WhatsApp నోటిఫికేషన్‌లు';

  @override
  String get notifEmail => 'ఇమెయిల్ నోటిఫికేషన్‌లు';

  @override
  String get notifLoadError => 'మీ నోటిఫికేషన్ సెట్టింగ్‌లను లోడ్ చేయలేకపోయాం.';

  @override
  String get returnsTitle => 'రిటర్న్‌లు & రిఫండ్‌లు';

  @override
  String get returnStatusRequested => 'అభ్యర్థించబడింది';

  @override
  String get returnStatusApproved => 'ఆమోదించబడింది';

  @override
  String get returnStatusRejected => 'తిరస్కరించబడింది';

  @override
  String get returnStatusPicked => 'తీసుకోబడింది';

  @override
  String get returnStatusRefunded => 'రిఫండ్ చేయబడింది';

  @override
  String get returnsEmptyTitle => 'ఇంకా రిటర్న్‌లు లేవు';

  @override
  String get returnsEmptyBody =>
      'మీరు అభ్యర్థించిన రిటర్న్‌లు మరియు రిఫండ్‌లు ఇక్కడ కనిపిస్తాయి.';

  @override
  String returnsOrderNumber(String code) {
    return 'ఆర్డర్ $code';
  }

  @override
  String get returnsReasonLabel => 'కారణం';

  @override
  String get returnsRefundLabel => 'రిఫండ్';

  @override
  String get returnRequestTitle => 'రిటర్న్ / రిఫండ్';

  @override
  String get returnRequestOrderLabel => 'ఆర్డర్';

  @override
  String get returnRequestReasonLabel => 'రిటర్న్‌కు కారణం';

  @override
  String get returnRequestSelectReason => 'ఒక కారణాన్ని ఎంచుకోండి';

  @override
  String get returnRequestDescriptionLabel => 'వివరణ (ఐచ్ఛికం)';

  @override
  String get returnRequestDescriptionHint =>
      'సమస్య గురించి మాకు మరింత చెప్పండి...';

  @override
  String get returnRequestSubmit => 'అభ్యర్థనను సమర్పించండి';

  @override
  String get returnRequestError =>
      'రిటర్న్‌ను అభ్యర్థించలేకపోయాం. దయచేసి మళ్లీ ప్రయత్నించండి.';

  @override
  String get returnRequestPhotosLabel => 'వస్తువు ఫోటోలు';

  @override
  String get returnRequestPhotosHint =>
      'వస్తువును, సమస్యను స్పష్టంగా చూపే ఫోటోలు జోడించండి. మా పికప్ భాగస్వామి వీటిని మీ ఇంటి వద్ద తనిఖీ చేస్తారు.';

  @override
  String get returnRequestAddPhoto => 'ఫోటో జోడించండి';

  @override
  String get returnRequestPhotoRequired =>
      'వస్తువు యొక్క కనీసం ఒక ఫోటోను జోడించండి.';

  @override
  String returnRequestPhotoLimit(int count) {
    return 'మీరు గరిష్ఠంగా $count ఫోటోలు జోడించవచ్చు.';
  }

  @override
  String get returnRequestRemovePhoto => 'ఫోటోను తీసివేయండి';

  @override
  String get returnReasonDamaged => 'దెబ్బతిన్న వస్తువు';

  @override
  String get returnReasonWrong => 'తప్పు వస్తువు';

  @override
  String get returnReasonQuality => 'నాణ్యత సమస్య';

  @override
  String get returnReasonChangedMind => 'నా అభిప్రాయం మార్చుకున్నాను';

  @override
  String get returnReasonOther => 'ఇతర';

  @override
  String get onboardingSlide1Caption => 'తాజా కిరాణా, వేగంగా డెలివరీ!';

  @override
  String get onboardingSlide1Title =>
      'తాజా కిరాణా మీ ఇంటి గుమ్మం వద్దకు డెలివరీ';

  @override
  String get onboardingSlide1Body =>
      'కూరగాయలు, పండ్లు, పాల ఉత్పత్తులు, గృహోపకరణాలు మరియు రోజువారీ కిరాణాను వేగవంతమైన డెలివరీతో ఆర్డర్ చేయండి.';

  @override
  String get onboardingSlide2Caption => 'ఇప్పుడు కొనండి, తర్వాత చెల్లించండి';

  @override
  String get onboardingSlide2Title =>
      'VS క్రెడిట్‌తో షాపింగ్ చేయండి, మీ నిబంధనలపై చెల్లించండి';

  @override
  String get onboardingSlide2Body =>
      'ఈరోజు మీకు అవసరమైనది కొనండి మరియు వారానికి లేదా నెలవారీ సౌకర్యవంతమైన క్రెడిట్‌తో తర్వాత చెల్లించండి — దాచిన ఛార్జీలు లేవు.';

  @override
  String get onboardingSlide3Caption => 'మీ VS స్కోర్‌ను పెంచుకోండి';

  @override
  String get onboardingSlide3Title =>
      'షాపింగ్ చేస్తూనే మీ క్రెడిట్ స్కోర్‌ను నిర్మించుకోండి';

  @override
  String get onboardingSlide3Body =>
      'సకాలంలో చేసే ప్రతి చెల్లింపు మీ VS స్కోర్‌ను బలోపేతం చేస్తుంది మరియు అధిక క్రెడిట్ పరిమితులు, మెరుగైన ఆఫర్‌లను అన్‌లాక్ చేస్తుంది.';

  @override
  String get onboardingGetStarted => 'ప్రారంభించండి';

  @override
  String get systemUpdateTitle => 'నవీకరణ అవసరం';

  @override
  String get systemUpdateBody =>
      'VS Mart యొక్క కొత్త వెర్షన్ ముఖ్యమైన మెరుగుదలలతో అందుబాటులో ఉంది. కొనసాగించడానికి దయచేసి Play Store నుండి నవీకరించండి.';

  @override
  String get systemUpdateNow => 'ఇప్పుడు నవీకరించండి';

  @override
  String get systemUpdatedCheckAgain => 'నేను నవీకరించాను — మళ్లీ తనిఖీ చేయండి';

  @override
  String get systemPlayStoreError =>
      'Play Store తెరవలేకపోయాం. నవీకరించడానికి దయచేసి \"VS Mart\" కోసం శోధించండి.';

  @override
  String get systemMaintenanceTitle => 'నిర్వహణలో ఉంది';

  @override
  String get systemMaintenanceBody =>
      'మేము కొన్ని మెరుగుదలలు చేస్తున్నాం మరియు త్వరలో తిరిగి వస్తాం. మీ సహనానికి ధన్యవాదాలు.';

  @override
  String get systemTryAgain => 'మళ్లీ ప్రయత్నించండి';

  @override
  String get systemNoInternetTitle => 'ఇంటర్నెట్ కనెక్షన్ లేదు';

  @override
  String get systemNoInternetBody =>
      'మీ కనెక్షన్‌ను తనిఖీ చేసి మళ్లీ ప్రయత్నించండి.';

  @override
  String get collectionConfirmTitle => 'చెల్లింపును నిర్ధారించండి';

  @override
  String get collectionConfirmLoadError => 'నిర్ధారణను లోడ్ చేయలేకపోయాం.';

  @override
  String get collectionConfirmNothingTitle => 'నిర్ధారించడానికి ఏమీ లేదు';

  @override
  String get collectionConfirmNothingBody =>
      'ప్రస్తుతం మీకు పెండింగ్ నగదు వసూలు ఏదీ లేదు.';

  @override
  String collectionConfirmCollecting(String name) {
    return '$name వసూలు చేస్తున్నారు';
  }

  @override
  String get collectionConfirmShareCode => 'ఈ కోడ్‌ను షేర్ చేయండి';

  @override
  String collectionConfirmSafetyWarning(String amount) {
    return 'మీరు $amount నగదు రూపంలో చెల్లిస్తున్నప్పుడు మాత్రమే ఈ కోడ్‌ను షేర్ చేయండి. లేకపోతే దీన్ని ఎప్పుడూ షేర్ చేయవద్దు.';
  }

  @override
  String get collectionConfirmDoneTitle => 'చెల్లింపు నిర్ధారించబడింది';

  @override
  String collectionConfirmDoneBody(String name, String amount) {
    return '$name కి $amount నగదు అందింది.';
  }

  @override
  String get locationPickerTitle => 'మీ స్థానాన్ని సెట్ చేయండి';

  @override
  String get locationConfirm => 'స్థానాన్ని నిర్ధారించండి';

  @override
  String get locationDragHint =>
      'పిన్ ఉంచడానికి మ్యాప్‌ను లాగండి లేదా నొక్కండి';

  @override
  String get locationCouldNotGet => 'మీ స్థానాన్ని పొందలేకపోయాం.';

  @override
  String get locationPermissionNeeded => 'స్థాన అనుమతి అవసరం.';

  @override
  String get locationSearchSubtitle =>
      'మీ ప్రాంతాన్ని కనుగొని, ఆపై మీ ఖచ్చితమైన స్థానంలో పిన్ ఉంచండి.';

  @override
  String get locationSearchHint =>
      'ప్రాంతం, వీధి లేదా ల్యాండ్‌మార్క్‌ను శోధించండి';

  @override
  String get locationPlaceLoadError =>
      'ఆ స్థలాన్ని లోడ్ చేయలేకపోయాం. మరొకటి ప్రయత్నించండి.';

  @override
  String get locationSearchUnavailable =>
      'శోధన ప్రస్తుతం అందుబాటులో లేదు. మీ ప్రస్తుత స్థానాన్ని ఉపయోగించండి, లేదా మీ కనెక్షన్‌ను తనిఖీ చేసి మళ్లీ ప్రయత్నించండి.';

  @override
  String get locationNoMatches => 'సరిపోలికలు లేవు. వేరే శోధనను ప్రయత్నించండి.';

  @override
  String get paymentReminderTitle => 'చెల్లింపు రిమైండర్‌లు';

  @override
  String get paymentReminderLoadError =>
      'మీ రిమైండర్ ప్రాధాన్యతలను లోడ్ చేయలేకపోయాం.';

  @override
  String get paymentReminderSaved => 'రిమైండర్ ప్రాధాన్యతలు సేవ్ చేయబడ్డాయి.';

  @override
  String get paymentReminderSaveError => 'ప్రాధాన్యతలను సేవ్ చేయలేకపోయాం.';

  @override
  String get paymentReminderHeadline => 'సమయానికి కొనసాగండి';

  @override
  String get paymentReminderSubtitle =>
      'ఆలస్య రుసుములను నివారించడానికి మరియు VS Mart తో ఆరోగ్యకరమైన క్రెడిట్ స్కోర్‌ను నిర్వహించడానికి మీ హెచ్చరికలను కాన్ఫిగర్ చేయండి.';

  @override
  String get paymentReminderEnableTitle => 'రిమైండర్‌లను ప్రారంభించండి';

  @override
  String get paymentReminderEnableSubtitle =>
      'మీ గడువు తేదీకి ముందు తెలియజేయబడతారు';

  @override
  String get paymentReminderWhenTitle => 'మేము మీకు ఎప్పుడు గుర్తు చేయాలి?';

  @override
  String get paymentReminderThreeDays => '3 రోజుల ముందు';

  @override
  String get paymentReminderThreeDaysSub => 'ముందుగా ప్రణాళిక వేయడానికి ఉత్తమం';

  @override
  String get paymentReminderOneDay => '1 రోజు ముందు';

  @override
  String get paymentReminderOneDaySub => 'త్వరిత రిమైండర్';

  @override
  String get paymentReminderOnDueDate => 'గడువు తేదీన';

  @override
  String get paymentReminderOnDueDateSub => 'చెల్లింపు ఉదయం';

  @override
  String get paymentReminderWeekBefore => 'ఒక వారం ముందు';

  @override
  String get paymentReminderWeekBeforeSub => 'గరిష్ట ముందస్తు సమయం';

  @override
  String get paymentReminderHowTitle => 'మేము మిమ్మల్ని ఎలా చేరుకోవాలి?';

  @override
  String get paymentReminderWhatsApp => 'WhatsApp';

  @override
  String get paymentReminderWhatsAppSub => 'తక్షణ సందేశ డెలివరీ';

  @override
  String get paymentReminderPush => 'పుష్ నోటిఫికేషన్';

  @override
  String get paymentReminderPushSub => 'నేరుగా మీ VS Mart యాప్‌కు';

  @override
  String get paymentReminderSms => 'SMS సందేశం';

  @override
  String get paymentReminderSmsSub => 'ప్రామాణిక టెక్స్ట్ సందేశం';

  @override
  String get paymentReminderPreferredTime => 'ఇష్టపడే సమయం';

  @override
  String get paymentReminderTimeOfDay => 'రోజులో సమయం';

  @override
  String get paymentReminderInfoBanner =>
      'రిమైండర్‌లను సెట్ చేయడం వల్ల మీరు ఆలస్య రుసుములను నివారించవచ్చు మరియు సకాలంలో చెల్లింపులను నిర్ధారించడం ద్వారా మీ క్రెడిట్ ఆరోగ్యంపై సానుకూల ప్రభావం చూపుతుంది.';

  @override
  String get paymentReminderSave => 'ప్రాధాన్యతలను సేవ్ చేయండి';

  @override
  String get supportFaqsHeadline => 'తరచుగా అడిగే ప్రశ్నలు';

  @override
  String get supportFaqsLoadError =>
      'తరచుగా అడిగే ప్రశ్నలను లోడ్ చేయలేకపోయాను.';

  @override
  String get supportNoFaqsMatch => 'మీ శోధనకు సరిపోయే FAQలు ఏవీ లేవు.';

  @override
  String get supportTeamHereToAssist =>
      'మా సహాయక బృందం మీకు సహాయపడటానికి సిద్ధంగా ఉంది.';

  @override
  String get supportContactSupport => 'మద్దతును సంప్రదించండి';

  @override
  String get supportAttachLimit => 'మీరు గరిష్టంగా 3 ఫైళ్లను జతచేయవచ్చు.';

  @override
  String get supportTicketSubmitted => 'టికెట్ సమర్పించబడింది';

  @override
  String get supportTapToUploadPhotos => 'ఫోటోలను అప్‌లోడ్ చేయడానికి నొక్కండి';

  @override
  String get supportMaxFilesSize => 'గరిష్టంగా 3 ఫైళ్లు, ఒక్కొక్కటి 5MB';

  @override
  String get supportRespondsWithin24h =>
      'మా బృందం సాధారణంగా 24 గంటల్లోగా స్పందిస్తుంది.';

  @override
  String supportTicketCode(String id) {
    return 'టికెట్ VS-TKT- $id';
  }

  @override
  String supportTicketOpened(String id) {
    return 'టికెట్ VS-TKT- $id తెరవబడింది';
  }

  @override
  String get supportSearchPrompt =>
      'సహాయం, ఆర్డర్‌లు, చెల్లింపులు, క్రెడిట్ సమస్యల కోసం వెతకండి…';

  @override
  String get supportTicketNotFound => 'టికెట్ కనుగొనబడలేదు.';

  @override
  String get supportCloseTicketQ => 'ఈ టికెట్‌ను మూసివేయాలా?';

  @override
  String get supportCloseTicketBody =>
      'ఇది సమస్య పరిష్కారమైందని మా బృందానికి తెలియజేస్తుంది మరియు దానిపై తదుపరి పనిని నిలిపివేస్తుంది. మీరు తర్వాత ఎప్పుడైనా కొత్త టికెట్‌ను లేవనెత్తవచ్చు.';

  @override
  String get supportTicketClosed => 'టికెట్ మూసివేయబడింది.';

  @override
  String settingsCouldNotOpen(String target) {
    return '$target తెరవలేకపోయాము.';
  }

  @override
  String get settingsOpenTargetDialer => 'డయలర్';

  @override
  String get settingsOpenTargetEmail => 'మీ ఇమెయిల్ యాప్';

  @override
  String get settingsOpenTargetLink => 'లింక్';

  @override
  String get settingsCompanyDescription =>
      'VS Mart అనేది రోజువారీ కిరాణా వాణిజ్యం మరియు సౌకర్యవంతమైన ఆర్థిక రుణాల మధ్య అంతరాన్ని తగ్గించే ఒక మార్గదర్శక హైబ్రిడ్ పర్యావరణ వ్యవస్థ. ఇది కుటుంబాలకు అత్యవసరమైనప్పుడు నిత్యావసరాలు నిరాటంకంగా అందేలా చూస్తుంది.';

  @override
  String get settingsMissionText =>
      'తాజా, సరసమైన కిరాణా సామాగ్రిని, నమ్మకమైన, సౌకర్యవంతమైన రుణ పరిష్కారాలతో కలిపి అందించడం ద్వారా సమాజాలకు సాధికారత కల్పించడం, తద్వారా ఒత్తిడి లేని షాపింగ్ అనుభవాన్ని సృష్టించడం.';

  @override
  String get settingsOfferGroceryTitle => 'కిరాణా సామాను కొనుగోలు';

  @override
  String get settingsOfferGrocerySubtitle => 'తాజా రోజువారీ అవసరాలు';

  @override
  String get settingsOfferCreditSubtitle => 'సౌకర్యవంతమైన చెల్లింపు ఎంపికలు';

  @override
  String get settingsOfferDeliveryTitle => 'డెలివరీ సేవలు';

  @override
  String get settingsOfferDeliverySubtitle =>
      'వేగవంతమైన మరియు నమ్మకమైన డెలివరీ';

  @override
  String get settingsOfferCollectionsTitle => 'డిజిటల్ సేకరణలు';

  @override
  String get settingsOfferCollectionsSubtitle => 'సజావుగా తిరిగి చెల్లించడం';

  @override
  String settingsAllRightsReserved(String app) {
    return '© 2026 $app . సర్వ హక్కులు సంరక్షించబడినవి.';
  }

  @override
  String get settingsBiometricLockSubtitle =>
      'VS Mart తెరవడానికి వేలిముద్ర / ఫేస్ ఐడి అవసరం';

  @override
  String get settingsNotifyNewLoginSubtitle =>
      'మీ ఖాతా సైన్ ఇన్ అయినప్పుడు నోటిఫికేషన్ పొందండి';

  @override
  String get settingsNotifyProfileChangesSubtitle =>
      'ఖాతా వివరాలు మారినప్పుడు నాకు తెలియజేయండి';

  @override
  String get settingsOtpSecurityNote =>
      'మీ VS Mart ఖాతా ప్రతి సైన్-ఇన్‌లో వన్-టైమ్ పాస్‌వర్డ్ ( OTP ) లాగిన్‌తో సురక్షితంగా ఉంటుంది.';

  @override
  String get settingsNoAccountContact =>
      'మేము మీ ఖాతా సంప్రదింపు వివరాలను కనుగొనలేకపోయాము. దయచేసి మళ్ళీ లాగిన్ అవ్వండి.';

  @override
  String get settingsDeletionRequested =>
      'తొలగింపు అభ్యర్థించబడింది — మేము దానిని ప్రాసెస్ చేసి మీ ఖాతాను తొలగిస్తాము.';

  @override
  String get billingCreditTab => 'క్రెడిట్';

  @override
  String get billingCreditPendingBody =>
      'మేము మీ వివరాలను ధృవీకరిస్తున్నాము. ఆమోదం పొందిన తర్వాత, సాధారణంగా కొన్ని గంటల్లోనే మీ VS Credit లైన్ ఇక్కడ అన్‌లాక్ అవుతుంది.';

  @override
  String get billingViewStatus => 'స్థితిని వీక్షించండి';

  @override
  String get billingCreditRejectedBody =>
      'మీ చివరి క్రెడిట్ దరఖాస్తు ఆమోదం పొందలేదు. మీరు మీ వివరాలను సమీక్షించుకుని, మళ్లీ దరఖాస్తు చేసుకోవచ్చు.';

  @override
  String get billingUnlockCredit => 'అన్‌లాక్ VS Credit';

  @override
  String get billingCreditApplyBody =>
      'VS Credit లైన్‌తో ఇప్పుడే షాపింగ్ చేసి, తర్వాత చెల్లించండి. దరఖాస్తు చేసుకోవడానికి త్వరిత KYC ధృవీకరణను పూర్తి చేయండి — దీనికి కేవలం కొన్ని నిమిషాలు మాత్రమే పడుతుంది.';

  @override
  String get billingApplyForCredit => 'క్రెడిట్ కోసం దరఖాస్తు చేసుకోండి';

  @override
  String get billingCreditEncryptedNote =>
      'మీ సమాచారం ఎన్‌క్రిప్ట్ చేయబడి, క్రెడిట్ ధృవీకరణ కోసం మాత్రమే ఉపయోగించబడుతుంది.';

  @override
  String get billingBenefitShopPayLater =>
      'ఇప్పుడే షాపింగ్ చేయండి, తర్వాత చెల్లించండి';

  @override
  String get billingBenefitFlexiblePlans =>
      'ఫ్లెక్సిబుల్ వీక్లీ / మంత్లీ ప్లాన్‌లు';

  @override
  String get billingBenefitMemberOffers => 'సభ్యులకు ప్రత్యేక ఆఫర్లు';

  @override
  String get billingBenefitBuildScore => 'మీ VS స్కోర్‌ను పెంచుకోండి';

  @override
  String get billingWhyVsCredit => 'VS Credit ఎందుకు?';

  @override
  String billingPercentUsed(int percent) {
    return '$percent % ఉపయోగించబడింది';
  }

  @override
  String billingUsedAmount(String amount) {
    return 'ఉపయోగించబడింది: $amount';
  }

  @override
  String billingTotalLimitAmount(String amount) {
    return 'మొత్తం పరిమితి: $amount';
  }

  @override
  String get billingCollectionRequestRaised =>
      'వసూలు అభ్యర్థన లేవనెత్తబడింది. మిమ్మల్ని సందర్శించడానికి ఒక ఏజెంట్‌ను నియమించడం జరుగుతుంది.';

  @override
  String get billingCollectionAddress => 'సేకరణ చిరునామా';

  @override
  String get billingRegisteredAddress => 'నమోదిత చిరునామా';

  @override
  String get billingAgentVisitAddress =>
      'ఏజెంట్ మీరు సేవ్ చేసుకున్న డెలివరీ చిరునామాకు వస్తారు';

  @override
  String get billingCollectionNotesHint =>
      'సేకరణ ఏజెంట్‌కు ఏవైనా సూచనలు (ఐచ్ఛికం)';

  @override
  String get billingCollectionAgentInfo =>
      'చెల్లింపును సురక్షితంగా వసూలు చేయడానికి, ఒక VS Mart కలెక్షన్ ఏజెంట్‌ను నియమించి, వారు మీ ప్రదేశానికి వస్తారు. ఏజెంట్ ఖరారైన తర్వాత మీకు తెలియజేయబడుతుంది.';

  @override
  String get billingAmountToCollect => 'వసూలు చేయవలసిన మొత్తం';

  @override
  String get billingEnterValidAmount =>
      'చెల్లుబాటు అయ్యే మొత్తాన్ని నమోదు చేయండి';

  @override
  String get billingRequest => 'అభ్యర్థన';

  @override
  String get billingCollectionsAppearHere =>
      'మీరు అభ్యర్థించిన నగదు సేకరణ పికప్‌లు ఇక్కడ కనిపిస్తాయి.';

  @override
  String billingRequestedOn(String date) {
    return 'అభ్యర్థించినది $date';
  }

  @override
  String get billingAddress => 'చిరునామా';

  @override
  String billingOrderDate(String order, String date) {
    return 'ఆర్డర్ $order • $date';
  }

  @override
  String get billingInvoiceLoadError => 'ఇన్‌వాయిస్‌ను లోడ్ చేయలేకపోయారు';

  @override
  String get billingOutstandingDue => 'చెల్లించవలసిన బకాయిలు';

  @override
  String get billingDuesLoadError => 'మీ బకాయిలను లోడ్ చేయలేకపోయాము.';

  @override
  String billingDueOnDate(String date) {
    return 'గడువు: $date';
  }

  @override
  String billingOverdueByDays(int days) {
    return '$days రోజులు గడువు దాటింది';
  }

  @override
  String billingDueInDays(int days) {
    return 'గడువు $days రోజులు';
  }

  @override
  String get billingTotalOutstandingAmount => 'మొత్తం బకాయి మొత్తం';

  @override
  String get billingPayBeforeDueNote =>
      'ఆరోగ్యకరమైన VS స్కోర్‌ను కొనసాగించడానికి మరియు ఆలస్య రుసుములను నివారించడానికి గడువు తేదీలోపు చెల్లించండి.';

  @override
  String get billingPayingTotalAmount => 'మొత్తం మొత్తాన్ని చెల్లించడం';

  @override
  String get billingReceiptDownloaded => 'రసీదు డౌన్‌లోడ్ చేయబడింది';

  @override
  String get billingCollectionRequested =>
      'సేకరణకు అభ్యర్థన పంపబడింది. ఒక ఏజెంట్‌ను నియమించడం జరుగుతుంది.';

  @override
  String get billingCollectionRequestError =>
      'అభ్యర్థనను లేవనెత్తలేకపోయాము. మళ్ళీ ప్రయత్నించండి.';

  @override
  String get billingPaymentFailed =>
      'చెల్లింపు విఫలమైంది. దయచేసి మళ్ళీ ప్రయత్నించండి.';

  @override
  String get billingProceedToPay => 'చెల్లించడానికి కొనసాగండి';

  @override
  String get billingOutstandingAmount => 'బకాయి మొత్తం';

  @override
  String get billingDebitCreditCard => 'డెబిట్ / క్రెడిట్ కార్డ్';

  @override
  String get billingNeftImpsTransfer => 'NEFT / IMPS బదిలీ';

  @override
  String get billingRequestAgentPickup => 'ఏజెంట్ పికప్‌ను అభ్యర్థించండి';

  @override
  String get billingCreditUpdated => 'క్రెడిట్ నవీకరించబడింది';

  @override
  String get billingStatementDownloaded => 'స్టేట్‌మెంట్ డౌన్‌లోడ్ చేయబడింది';

  @override
  String get billingNoTransactionsInCycle => 'ఈ సైకిల్‌లో లావాదేవీలు లేవు.';

  @override
  String billingPayAmount(String amount) {
    return '$amount చెల్లించండి';
  }

  @override
  String get billingStatusDue => 'కారణంగా';

  @override
  String get billingGenerated => 'ఉత్పత్తి చేయబడింది';

  @override
  String billingBalanceAmount(String amount) {
    return 'బ్యాలెన్స్ $amount';
  }

  @override
  String billingPaymentDue(String date) {
    return 'చెల్లింపు గడువు తేదీ $date';
  }

  @override
  String billingAmountDueMin(String amount, String min) {
    return 'చెల్లించవలసిన $amount $min';
  }

  @override
  String billingAmountDueShort(String amount) {
    return 'చెల్లించవలసిన మొత్తం $amount';
  }

  @override
  String get billingPay => 'చెల్లించండి';

  @override
  String get kycDobHelpText => 'పుట్టిన తేదీ ( PAN ప్రకారం)';

  @override
  String get kycApplyVsCredit => 'VS Credit కోసం దరఖాస్తు చేసుకోండి';

  @override
  String get kycStep1VerifyDetails =>
      '2 దశలలో 1వది · మీ వివరాలను ధృవీకరించుకోండి';

  @override
  String get kycDetailsIntro =>
      'మీ PAN ఉన్న విధంగా మీ వివరాలను నమోదు చేయండి. మీ గుర్తింపును ధృవీకరించడానికి, మేము మీ రిజిస్టర్డ్ నంబర్‌కు మీ CIBIL స్కోర్‌ను పొందుతాము.';

  @override
  String get kycNameAsPerPan => 'PAN ప్రకారం పేరు';

  @override
  String get kycFullNameHint => 'ఉదా శ్రీనివాసు మగపు';

  @override
  String get kycSelectDob => 'మీ పుట్టిన తేదీని ఎంచుకోండి';

  @override
  String get kycCheckCibil => 'CIBIL తనిఖీ చేయండి';

  @override
  String get kycIdentityVerified => 'గుర్తింపు ధృవీకరించబడింది';

  @override
  String kycCibilScore(String score) {
    return 'CIBIL $score';
  }

  @override
  String get kycStep2Documents => '2వ దశ · పత్రాలను అప్‌లోడ్ చేయండి';

  @override
  String get kycDocsIntro =>
      'మీ Aadhaar మరియు PAN కార్డుల రెండు వైపులా స్పష్టమైన ఫోటోలు. ఒక ఏజెంట్ వాటిని ధృవీకరిస్తారు.';

  @override
  String get kycAadhaarFront => 'Aadhaar — ముందు';

  @override
  String get kycAadhaarBack => 'Aadhaar — వెనుకకు';

  @override
  String get kycPanFront => 'PAN — ముందు';

  @override
  String get kycPanBack => 'PAN — వెనుక';

  @override
  String get kycSubmitForVerification => 'ధృవీకరణ కోసం సమర్పించండి';

  @override
  String get kycApplicationSubmitted => 'దరఖాస్తు సమర్పించబడింది';

  @override
  String get kycApplicationSubmittedBody =>
      'మీ పత్రాలను ధృవీకరించడానికి ఒక ఏజెంట్‌ను నియమిస్తారు. వారు ఆమోదించిన తర్వాత మీ VS Credit పరిమితి అన్‌లాక్ అవుతుంది.';

  @override
  String get kycYourCibilScore => 'మీ CIBIL స్కోరు';

  @override
  String get kycTapToChange => 'మార్చడానికి నొక్కండి';

  @override
  String get kycTapToUpload => 'అప్‌లోడ్ చేయడానికి నొక్కండి';

  @override
  String get kycConsentText =>
      'నా గుర్తింపును ధృవీకరించడానికి మరియు నా రుణ అర్హతను అంచనా వేయడానికి, బ్యూరో నుండి నా క్రెడిట్ స్కోర్‌ను పొందడానికి నేను VS Mart అధికారం ఇస్తున్నాను.';

  @override
  String get kycLiveSelfie => 'లైవ్ సెల్ఫీ';

  @override
  String get kycMobileVerified => 'మొబైల్ ధృవీకరించబడింది';

  @override
  String get kycAddressAdded => 'చిరునామా జోడించబడింది';

  @override
  String get kycStatusLoadError => 'మీ ధృవీకరణ స్థితిని లోడ్ చేయలేకపోయాము.';

  @override
  String get kycResubmitDocuments => 'పత్రాలను తిరిగి సమర్పించండి';

  @override
  String get kycCompleteToUnlock =>
      'VS Credit ప్రయోజనాలను పొందడానికి ధృవీకరణను పూర్తి చేయండి.';

  @override
  String get kycInstantVerification => 'తక్షణ ధృవీకరణ';

  @override
  String get kycInstantVerifyBody =>
      'ఒక్క నిమిషంలో మీ PAN మరియు క్రెడిట్ స్కోర్‌తో ధృవీకరించుకోండి';

  @override
  String kycStepsCompleted(int completed, int total) {
    return '$total దశల్లో $completed పూర్తయ్యాయి';
  }

  @override
  String get kycBenefitOnApproval => 'ఆమోదంపై';

  @override
  String get kycBenefitFlexiblePlans => 'ఫ్లెక్సిబుల్ ప్లాన్‌లు';

  @override
  String get kycBenefitWeeklyMonthly => 'వారానికి / నెలకు';

  @override
  String get kycBenefitExclusiveOffers => 'ప్రత్యేక ఆఫర్లు';

  @override
  String get kycBenefitMemberOnly => 'సభ్యులకు మాత్రమే';

  @override
  String get kycBenefitBuildCredit => 'క్రెడిట్ నిర్మించుకోండి';

  @override
  String get kycUnlockBenefits => 'అన్‌లాక్ VS Credit ప్రయోజనాలు';

  @override
  String get kycSecurityNote =>
      'మీ సమాచారం ఎన్‌క్రిప్ట్ చేయబడి, బ్యాంకు-స్థాయి భద్రతా ప్రమాణాలను అనుసరించి సురక్షితంగా నిల్వ చేయబడుతుంది.';

  @override
  String get kycSecurityBannerBody =>
      'మీ పూర్తి క్రెడిట్ పరిమితిని పొందడానికి మరియు ఆర్‌బిఐ నిబంధనలకు అనుగుణంగా ఉండేలా చూసుకోవడానికి KYC ధృవీకరణ అవసరం. మేము బ్యాంక్-గ్రేడ్ ఎన్‌క్రిప్షన్‌ను ఉపయోగిస్తాము.';

  @override
  String get kycCaptionVerified =>
      'అవసరమైన పత్రాలన్నీ విజయవంతంగా ధృవీకరించబడ్డాయి.';

  @override
  String get kycCaptionPending =>
      'మీ పత్రాలు సమీక్షలో ఉన్నాయి. దీనికి సాధారణంగా 1–2 రోజులు పడుతుంది.';

  @override
  String get kycCaptionRejected =>
      'కొన్ని పత్రాలను ధృవీకరించలేకపోయాము. దయచేసి మళ్ళీ సమర్పించండి.';

  @override
  String get kycCaptionNotStarted =>
      'మీ పూర్తి క్రెడిట్ పరిమితిని పొందడానికి మీ KYC పూర్తి చేయండి.';

  @override
  String kycPercentComplete(int percent) {
    return '$percent % పూర్తయింది';
  }

  @override
  String get kycStartCardBody =>
      'మీ గుర్తింపును ధృవీకరించుకోవడానికి మీ Aadhaar , PAN మరియు ఒక సెల్ఫీని సమర్పించండి.';

  @override
  String get kycSubmitted => 'సమర్పించబడింది';

  @override
  String get commonOr => 'లేదా';

  @override
  String discountPercentOff(int percent) {
    return '$percent % తగ్గింపు';
  }

  @override
  String get serviceCheckingArea => 'మీ ప్రాంతాన్ని తనిఖీ చేస్తున్నాము…';

  @override
  String get serviceConfirmingDelivery =>
      'మీరు ఉన్న చోటకే మేము డెలివరీ చేస్తామని నిర్ధారిస్తున్నాము.';

  @override
  String get serviceSetLocationTitle =>
      'కొనసాగించడానికి మీ స్థానాన్ని సెట్ చేయండి';

  @override
  String get serviceNotInAreaTitle => 'VS Mart ఇంకా మీ ప్రాంతంలో లేదు';

  @override
  String get serviceCouldntConfirmBody =>
      'మేము మీ లొకేషన్‌ను నిర్ధారించలేకపోయాము. VS Mart మీ సమీపంలో డెలివరీ చేస్తుందో లేదో మేము తనిఖీ చేసేలా దాన్ని సెట్ చేయండి.';

  @override
  String get serviceExpandingBody =>
      'మేము వేగంగా విస్తరిస్తున్నాము. మీకు సమీపంలో సేవలు అందుబాటులో ఉన్న ప్రాంతం నుండి షాపింగ్ చేయడానికి మీ లొకేషన్‌ను మార్చుకోండి.';

  @override
  String get serviceNotifyWhenHere =>
      'మీరు ఇక్కడికి వచ్చినప్పుడు నాకు తెలియజేయండి';

  @override
  String get serviceLocationOffNote =>
      'మీ ఫోన్‌లో లొకేషన్ ఆఫ్ చేయబడి ఉంది. దాన్ని ఆన్ చేసి, మళ్ళీ ప్రయత్నించండి.';

  @override
  String get serviceOpenLocationSettings => 'స్థాన సెట్టింగ్‌లను తెరవండి';

  @override
  String get serviceLocationBlockedNote =>
      'VS Mart కోసం లొకేషన్ అనుమతి నిరోధించబడింది. సెట్టింగ్స్‌లో దాన్ని ఎనేబుల్ చేసి, మళ్లీ ప్రయత్నించండి.';

  @override
  String get serviceOpenAppSettings => 'యాప్ సెట్టింగ్‌లను తెరవండి';

  @override
  String get serviceNoGpsFixNote =>
      'GPS ఫిక్స్ లభించలేదు. కిటికీ దగ్గరకు వెళ్లండి లేదా బయటకు వెళ్లి మళ్లీ ప్రయత్నించండి, లేదా దానికి బదులుగా మీ ప్రాంతం కోసం శోధించండి.';

  @override
  String get serviceDontDeliverThereNote =>
      'మేము ఇంకా అక్కడ డెలివరీ చేయడం లేదు. వేరే ప్రదేశంలో ప్రయత్నించండి.';

  @override
  String get serviceChangeLocationBody =>
      'మీ ప్రస్తుత స్థానాన్ని ఉపయోగించండి, లేదా మీ ప్రాంతంలో వెతికి పిన్‌ను డ్రాప్ చేయండి.';

  @override
  String get serviceUseMyCurrentLocation =>
      'నా ప్రస్తుత స్థానాన్ని ఉపయోగించండి';

  @override
  String get serviceSearchAreaDropPin => 'శోధన ప్రాంతం & డ్రాప్ పిన్';

  @override
  String get serviceOpenSettings => 'సెట్టింగ్‌లను తెరవండి';

  @override
  String get serviceEnterValidPhone => 'సరైన ఫోన్ నంబర్‌ను నమోదు చేయండి';

  @override
  String get serviceNotifyBody =>
      'మీ నంబర్ ఇవ్వండి, మీ ప్రాంతంలో VS Mart డెలివరీ ప్రారంభించిన వెంటనే మేము మీకు మెసేజ్ చేస్తాము.';

  @override
  String get serviceNameOptional => 'పేరు (ఐచ్ఛికం)';

  @override
  String get servicePhoneHintExample => 'ఉదా +9198XXXXXXXX';

  @override
  String get serviceWellNotifyYou => 'మేము మీకు తెలియజేస్తాము';

  @override
  String get serviceNotifySuccessBody =>
      'ధన్యవాదాలు! మేము మీ ఆసక్తిని నమోదు చేసుకున్నాము మరియు మీ సమీపంలో డెలివరీ ప్రారంభించిన వెంటనే మీకు సందేశం పంపుతాము.';

  @override
  String get wishlistBrowseProducts => 'ఉత్పత్తులను బ్రౌజ్ చేయండి';

  @override
  String get wishlistPriceDrop => 'ధర తగ్గుదల';

  @override
  String wishlistRemoved(String name) {
    return 'విష్‌లిస్ట్ నుండి $name తొలగించబడింది';
  }

  @override
  String get searchUnderPrice => '₹99 లోపు';

  @override
  String searchResultsFound(int count) {
    return '$count ఫలితాలు కనుగొనబడ్డాయి';
  }

  @override
  String searchNoResultsFor(String query) {
    return 'మేము \" $query \" కోసం ఏమీ కనుగొనలేకపోయాము.';
  }

  @override
  String get searchSortPrefix => 'క్రమబద్ధీకరించు: ';

  @override
  String searchFiltersApplied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ఫిల్టర్‌లు వర్తించబడ్డాయి',
      one: '1 ఫిల్టర్ వర్తించబడింది',
    );
    return '$_temp0';
  }

  @override
  String get searchForPrefix => 'వెతకండి ';

  @override
  String reviewsTooLong(int max) {
    return 'మీ సమీక్ష చాలా పొడవుగా ఉంది (గరిష్టంగా $max అక్షరాలు).';
  }

  @override
  String reviewsRatingValue(int rating) {
    return '5 నక్షత్రాలకు గాను $rating';
  }

  @override
  String reviewsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count సమీక్షలు',
      one: '1 సమీక్ష',
    );
    return '$_temp0';
  }

  @override
  String get reviewsNoneYet =>
      'ఇంకా సమీక్షలు లేవు — మొదటి వ్యక్తి మీరే అవ్వండి';

  @override
  String reviewsRateStars(int star) {
    String _temp0 = intl.Intl.pluralLogic(
      star,
      locale: localeName,
      other: '$star స్టార్‌లు ఇవ్వండి',
      one: '1 స్టార్ ఇవ్వండి',
    );
    return '$_temp0';
  }

  @override
  String get referralCodeHint => 'ఉదా. VS00042';

  @override
  String get referralTermsApply => 'నిబంధనలు మరియు షరతులు వర్తిస్తాయి';

  @override
  String referralEarnPerReferral(String amount) {
    return 'ప్రతి విజయవంతమైన రిఫరల్‌కు $amount సంపాదించండి';
  }

  @override
  String get referralNoneYet =>
      'ఇంకా రిఫరల్స్ లేవు — సంపాదించడం ప్రారంభించడానికి ఆహ్వానించండి';

  @override
  String referralSuccessfulCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count విజయవంతమైన రెఫరల్‌లు',
      one: '1 విజయవంతమైన రెఫరల్',
    );
    return '$_temp0';
  }

  @override
  String get referralYourCode => 'మీ రిఫరల్ కోడ్';

  @override
  String get referralStepShareBody =>
      'మీ ప్రత్యేకమైన లింక్ లేదా కోడ్‌ను పంచుకోండి.';

  @override
  String get referralStepRegisterBody =>
      'వారు మీ కోడ్‌ని ఉపయోగించి నమోదు చేసుకుంటారు.';

  @override
  String get referralStepOrderBody => 'వారు తమ మొదటి సరైన ఆర్డర్‌ను ఇస్తారు.';

  @override
  String referralStepEarnBody(String amount) {
    return 'మీ వాలెట్‌కు $amount జోడించబడుతుంది.';
  }

  @override
  String get offersCouldntLoadDeals => 'డీల్స్ లోడ్ చేయలేకపోయాను.';

  @override
  String get offersCouldntLoadCoupons => 'కూపన్‌లను లోడ్ చేయలేకపోయాను.';

  @override
  String get offersUpTo60Off => '60% వరకు తగ్గింపు';

  @override
  String get offersOnGroceries => 'కిరాణా సామాగ్రి & నిత్యావసరాలపై';

  @override
  String get offersTodaysDeals => 'నేటి ఆఫర్లు';

  @override
  String get offersMegaSavings => 'ఈరోజు భారీ పొదుపులు';

  @override
  String get offersUpTo60OffProduce =>
      'తాజా ఉత్పత్తులు మరియు నిత్యావసరాలపై 60% వరకు తగ్గింపు';

  @override
  String get offersFilterFlashSale => 'ఫ్లాష్ సేల్';

  @override
  String get offersFilterTopDiscounts => 'అత్యధిక తగ్గింపులు';

  @override
  String get offersFilterBuy1Get1 => 'ఒకటి కొంటే ఒకటి ఉచితం';

  @override
  String get offersOnlyFiveLeft => 'ఇంకా 5 మాత్రమే మిగిలాయి!';

  @override
  String get offersClaimedPercent => '80% క్లెయిమ్ చేయబడింది';

  @override
  String offersCodeLabel(String code) {
    return 'కోడ్: $code';
  }

  @override
  String get loyaltyRedeemPoints => 'పాయింట్లను రీడీమ్ చేసుకోండి';

  @override
  String get loyaltyRewardPoints => 'రివార్డ్ పాయింట్లు';

  @override
  String get loyaltyPointsAvailable => 'అందుబాటులో ఉన్న పాయింట్లు';

  @override
  String loyaltyLifetimeEarned(String points) {
    return 'జీవితకాలంలో సంపాదించినవి: $points పాయింట్లు';
  }

  @override
  String get loyaltyNoActivity => 'ఇంకా పాయింట్ల కార్యకలాపం లేదు';

  @override
  String get loyaltyNoActivityBody =>
      'మీ చరిత్రను ఇక్కడ చూసేందుకు పాయింట్లను సంపాదించండి మరియు రీడీమ్ చేసుకోండి.';

  @override
  String get loyaltyPointsEarned => 'సంపాదించిన పాయింట్లు';

  @override
  String get loyaltyPointsRedeemed => 'పాయింట్లు రీడీమ్ చేయబడ్డాయి';

  @override
  String get loyaltyPointsExpired => 'పాయింట్లు గడువు ముగిశాయి';

  @override
  String get loyaltyPointsAdjustment => 'పాయింట్ల సర్దుబాటు';

  @override
  String get loyaltyEnterValidPoints => 'సరైన పాయింట్ల సంఖ్యను నమోదు చేయండి';

  @override
  String loyaltyOnlyHavePoints(String points) {
    return 'మీకు కేవలం $points పాయింట్లు మాత్రమే ఉన్నాయి';
  }

  @override
  String loyaltyPointsAvailableSentence(String points) {
    return 'మీకు $points పాయింట్లు అందుబాటులో ఉన్నాయి.';
  }

  @override
  String get loyaltyPointsToRedeem => 'రీడీమ్ చేసుకోవడానికి పాయింట్లు';

  @override
  String get loyaltyPointsHint => 'ఉదాహరణకు 100';

  @override
  String get loyaltyRedeem => 'విమోచించు';

  @override
  String get notificationsAllCaughtUp => 'మీరు అన్ని విషయాలు తెలుసుకున్నారు.';

  @override
  String get notificationsYesterday => 'నిన్న';

  @override
  String homeOrderNumber(String id) {
    return 'ఆర్డర్ సంఖ్య $id';
  }

  @override
  String get homeCouldntLoad => 'లోడ్ చేయలేకపోయింది';

  @override
  String get checkoutCouldNotPlaceOrder =>
      'ఆర్డర్ చేయలేకపోయారు. దయచేసి మీ కార్ట్‌ను సమీక్షించండి.';

  @override
  String checkoutQty(int count) {
    return 'పరిమాణం $count';
  }

  @override
  String checkoutCouponAppliedOff(String code, String amount) {
    return '“$code” వర్తింపజేయబడింది — $amount తగ్గింపు';
  }

  @override
  String checkoutDueDate(String date) {
    return '$date';
  }

  @override
  String get paymentCouldNotComplete =>
      'చెల్లింపు పూర్తి కాలేదు. మీ కార్ట్ మరియు చిరునామాను తనిఖీ చేయండి.';

  @override
  String get paymentNotCompleted =>
      'చెల్లింపు పూర్తి కాలేదు. మీ ఆర్డర్ సేవ్ చేయబడింది — మీరు \'నా ఆర్డర్‌లు\' నుండి మళ్లీ ప్రయత్నించవచ్చు.';

  @override
  String get cartItemsUnavailableTitle => 'కొన్ని వస్తువులు అందుబాటులో లేవు';

  @override
  String get cartItemsUnavailableBody =>
      'మీ స్టోర్‌లో ఇవి స్టాక్ అయిపోయాయి. కొనసాగించడానికి వీటిని తొలగించండి.';

  @override
  String get cartRemoveAndContinue => 'తీసివేసి కొనసాగించండి';

  @override
  String get cartReviewCart => 'కార్ట్‌ను సమీక్షించండి';

  @override
  String get cartSignInBody =>
      'మీ ఆర్డర్‌ను నమోదు చేయడానికి మరియు చెల్లించడానికి ఖాతాను సృష్టించండి లేదా సైన్ ఇన్ చేయండి. మీ కార్ట్ మీ కోసం సిద్ధంగా ఉంటుంది.';

  @override
  String get cartTotalEstimateError =>
      'తాజా మొత్తం పొందలేకపోయాము — అంచనా చూపబడుతోంది. మళ్ళీ ప్రయత్నించడానికి నొక్కండి.';

  @override
  String ordersOrderNumber(Object id) {
    return 'ఆర్డర్ సంఖ్య $id';
  }

  @override
  String get ordersCancelConfirmTitle => 'ఆర్డర్‌ను రద్దు చేయాలా?';

  @override
  String get ordersCancelConfirmBody =>
      'ఈ ఆర్డర్‌ను రద్దు చేయాలా? దీన్ని వెనక్కి తీసుకోలేరు.';

  @override
  String get ordersKeepOrder => 'క్రమాన్ని పాటించండి';

  @override
  String get ordersCancelled => 'ఆర్డర్ రద్దు చేయబడింది';

  @override
  String get ordersTimeline => 'ఆర్డర్ టైమ్‌లైన్';

  @override
  String ordersItemQuantity(Object name, int quantity) {
    return '$name × $quantity';
  }

  @override
  String get ordersPayment => 'చెల్లింపు';

  @override
  String get ordersCreditUsed => 'క్రెడిట్ ఉపయోగించబడింది';

  @override
  String get ordersOrderPlaced => 'ఆర్డర్ ఇవ్వబడింది';

  @override
  String get ordersOrderStatus => 'ఆర్డర్ స్థితి';

  @override
  String ordersArrivingIn(String eta) {
    return '$etaలో వస్తుంది';
  }

  @override
  String get ordersOnTheWayHeadline => 'మీ ఆర్డర్ పంపబడింది';

  @override
  String get ordersWeWillUpdate => 'తదుపరి చర్యల గురించి మీకు తెలియజేస్తాము.';

  @override
  String get ordersContactWhenAssigned =>
      'రైడర్‌ను కేటాయించిన తర్వాత సంప్రదింపు వివరాలు కనిపిస్తాయి.';

  @override
  String get ordersDialerError => 'డయలర్‌ను తెరవలేకపోయాను.';

  @override
  String get ordersDeliveryPartner => 'డెలివరీ భాగస్వామి';

  @override
  String get ordersRiderOnTheWay => 'దారిలో';

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
      'మీ డెలివరీ చిరునామాకు లొకేషన్‌ను గుర్తించిన తర్వాత లైవ్ మ్యాప్ కనిపిస్తుంది.';

  @override
  String ordersMoreItems(int count) {
    return '+ $count మరిన్ని';
  }

  @override
  String ordersItemsAddedToCart(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count వస్తువులు కార్ట్‌కు జోడించబడ్డాయి',
      one: '1 వస్తువు కార్ట్‌కు జోడించబడింది',
    );
    return '$_temp0';
  }

  @override
  String get ordersItemsUnavailable => 'ఆ వస్తువులు ప్రస్తుతం అందుబాటులో లేవు';

  @override
  String get ordersOrderedAt => 'ఆర్డర్ చేయబడింది';

  @override
  String get ordersDeliveredAt => 'డెలివరీ చేయబడింది';

  @override
  String get ordersFeedbackThanks => 'మీ అభిప్రాయానికి ధన్యవాదాలు!';

  @override
  String get ordersYouRated => 'మీరు ఈ ఆర్డర్‌కు రేటింగ్ ఇచ్చారు';

  @override
  String get ordersHowWasDelivery => 'మీ డెలివరీ ఎలా జరిగింది?';

  @override
  String get ordersFeedbackHelps =>
      'మీ అభిప్రాయం మాకు మెరుగుపడటానికి సహాయపడుతుంది.';

  @override
  String ordersAgentDelivered(Object name) {
    return '$name ఈ ఆర్డర్‌ను డెలివరీ చేశారు.';
  }

  @override
  String get ordersFeedbackHint => 'ఏమైనా జోడించాలనుకుంటున్నారా? (ఐచ్ఛికం)';

  @override
  String get ordersSendFeedback => 'అభిప్రాయాన్ని పంపండి';

  @override
  String ordersStarCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count స్టార్‌లు',
      one: '1 స్టార్',
    );
    return '$_temp0';
  }

  @override
  String get profileLogoutConfirmBody =>
      'మీ ఖాతాను యాక్సెస్ చేయడానికి మీరు మళ్లీ సైన్ ఇన్ చేయవలసి ఉంటుంది.';

  @override
  String get profileBrowsingAsGuest => 'మీరు అతిథిగా బ్రౌజ్ చేస్తున్నారు';

  @override
  String get profileGuestSignInBody =>
      'ఆర్డర్‌లు ఇవ్వడానికి, డెలివరీలను ట్రాక్ చేయడానికి మరియు VS Credit అన్‌లాక్ చేయడానికి సైన్ ఇన్ చేయండి.';

  @override
  String get profileGuest => 'అతిథి';

  @override
  String profileCreditAmount(Object amount) {
    return 'క్రెడిట్ $amount';
  }

  @override
  String profileScoreValue(Object score) {
    return 'స్కోరు $score';
  }

  @override
  String profileUsedAmount(Object amount) {
    return 'ఉపయోగించబడింది: $amount';
  }

  @override
  String profileLimitAmount(Object amount) {
    return 'పరిమితి: $amount';
  }

  @override
  String get profileAddresses => 'చిరునామాలు';

  @override
  String get profilePayments => 'చెల్లింపులు';

  @override
  String get profileSupport => 'మద్దతు';

  @override
  String get profileMonthlyStatement => 'నెలవారీ నివేదిక';

  @override
  String get profileOutstandingDue => 'చెల్లించవలసిన బకాయిలు';

  @override
  String get profileCreditUsage => 'క్రెడిట్ వినియోగం';

  @override
  String get profileVsScoreDetails => 'VS స్కోర్ వివరాలు';

  @override
  String get profileNoSavedAddress => 'ఇంకా చిరునామా సేవ్ చేయలేదు.';

  @override
  String get profilePaymentUpi => 'UPI చెల్లింపు';

  @override
  String get profilePaymentCard => 'కార్డ్ చెల్లింపు';

  @override
  String get profilePaymentBankTransfer => 'బ్యాంకు బదిలీ';

  @override
  String get profilePaymentCashCollection => 'నగదు సేకరణ';

  @override
  String get profileViewHistory => 'చరిత్రను వీక్షించండి';

  @override
  String get profileKycAadhaar => 'Aadhaar';

  @override
  String get profileKycSelfie => 'సెల్ఫీ';

  @override
  String get profileKycHouse => 'ఇంటి ధృవీకరణ';

  @override
  String profileActiveCoupons(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count యాక్టివ్ కూపన్‌లు',
      one: '1 యాక్టివ్ కూపన్',
    );
    return '$_temp0';
  }

  @override
  String get profileLanguageEnglish => 'భాష (ఇంగ్లీష్)';

  @override
  String get profileAboutVsMart => 'VS Mart గురించి';

  @override
  String get profileCareers => 'కెరీర్లు';

  @override
  String get profileYou => 'మీరు';

  @override
  String get profilePrimaryHolder => 'ప్రాథమిక ఖాతాదారుడు';

  @override
  String get profileFamilyMember => 'కుటుంబ సభ్యుడు';

  @override
  String get profileInvitationPending => 'ఆహ్వానం పెండింగ్‌లో ఉంది';

  @override
  String get profileHouseholdMember => 'ఇంటి సభ్యుడు';

  @override
  String profileMemberRemoved(Object name) {
    return '$name తొలగించబడింది.';
  }

  @override
  String get profileRelationshipHint => 'సంబంధం (ఉదా: జీవిత భాగస్వామి)';

  @override
  String get profileInvite => 'ఆహ్వానించండి';

  @override
  String profileInviteSent(Object phone) {
    return '$phone కు ఆహ్వానం పంపబడింది.';
  }

  @override
  String get profileHouseholdLoadError => 'మీ ఇంటిని లోడ్ చేయలేకపోయాము.';

  @override
  String get profileFamilySubtitle =>
      'మీ కుటుంబం కోసం ఉమ్మడి క్రెడిట్ పరిమితులు మరియు షాపింగ్ ప్రొఫైల్‌లను నిర్వహించండి.';

  @override
  String get profileSharedLimitUsage => 'భాగస్వామ్య పరిమితి వినియోగం';

  @override
  String get profileAddHouseholdMember => 'ఇంటి సభ్యుడిని జోడించండి';

  @override
  String get profileAddMemberBody =>
      'మీ VS Mart క్రెడిట్ పరిమితి మరియు షాపింగ్ జాబితాలను పంచుకోవడానికి కుటుంబాన్ని ఆహ్వానించండి.';

  @override
  String get profileUpdated => 'ప్రొఫైల్ నవీకరించబడింది';

  @override
  String get profilePhotoUpdated => 'ప్రొఫైల్ ఫోటో అప్‌డేట్ చేయబడింది.';

  @override
  String get profileNameHint => 'ఉదాహరణకు జేన్ డో';

  @override
  String get profileEmailHint => 'you@example.com';

  @override
  String get catalogProductNotFound => 'ఉత్పత్తి కనుగొనబడలేదు.';

  @override
  String get catalogRemovedFromWishlist => 'విష్‌లిస్ట్ నుండి తొలగించబడింది';

  @override
  String get catalogAddedToWishlist => 'విష్‌లిస్ట్‌కు జోడించబడింది';

  @override
  String get catalogShareSheetError => 'షేర్ షీట్‌ను తెరవలేకపోయాను.';

  @override
  String get catalogDefaultDescription =>
      'పొలం నుండి తాజాగా, నాణ్యత కోసం చేతితో ఎంపిక చేసి, అత్యంత తాజాదనంతో సరఫరా చేయబడుతుంది.';

  @override
  String get catalogEligibleForCredit => 'VS Credit అర్హులు';

  @override
  String catalogBrowseAllIn(Object name) {
    return '$name లోని అన్నింటినీ బ్రౌజ్ చేయండి';
  }

  @override
  String get catalogViewProducts => 'ఉత్పత్తులను వీక్షించండి';

  @override
  String get catalogDecreaseQuantity => 'పరిమాణాన్ని తగ్గించండి';

  @override
  String get catalogIncreaseQuantity => 'పరిమాణాన్ని పెంచండి';

  @override
  String get catalogHandpickedDaily =>
      'విశ్వసనీయమైన పొలాల నుండి ప్రతిరోజూ చేతితో ఎంపిక చేయబడినవి';

  @override
  String get catalogNothingHere => 'ఇక్కడ ఏమీ లేదు';

  @override
  String get catalogFreshPicksIn => 'తాజా ఎంపికలు';

  @override
  String get catalogHandpickedQuality =>
      'చేతితో ఎంపిక చేయబడినవి, నాణ్యత తనిఖీ చేయబడినవి, వేగంగా డెలివరీ చేయబడినవి';

  @override
  String get catalogShareLinkCopied => 'షేర్ లింక్ కాపీ చేయబడింది';

  @override
  String catalogAddedToCart(Object name) {
    return '$name కార్ట్‌కు జోడించబడింది';
  }

  @override
  String catalogPercentOff(Object percent) {
    return '$percent % తగ్గింపు';
  }

  @override
  String catalogPriceOnCredit(Object price) {
    return 'VS Credit $price';
  }

  @override
  String catalogPriceRange(Object min, Object max) {
    return '₹ $min – ₹ $max';
  }

  @override
  String catalogDiscountOff(Object percent) {
    return '$percent %+ తగ్గింపు';
  }

  @override
  String get verificationAadhaarInvalid =>
      'చెల్లుబాటు అయ్యే 12 అంకెల Aadhaar నంబర్‌ను నమోదు చేయండి';

  @override
  String get verificationOtpSentAadhaar =>
      'మీ Aadhaar అనుసంధానిత మొబైల్‌కు పంపబడిన OTP';

  @override
  String get verificationEnterOtpReceived => 'మీకు వచ్చిన OTP నమోదు చేయండి';

  @override
  String get verificationAadhaarVerified => 'Aadhaar ధృవీకరించబడింది';

  @override
  String get verificationCouldNotCaptureImage => 'చిత్రాన్ని తీయలేకపోయాను';

  @override
  String get verificationUploadAadhaarBoth =>
      'దయచేసి Aadhaar ముందు మరియు వెనుక పత్రాలను అప్‌లోడ్ చేయండి';

  @override
  String get verificationRequiredForCredit =>
      'VS Credit యాక్టివేట్ చేయడానికి అవసరం.';

  @override
  String get verificationOtpOptionalNote =>
      'ఐచ్ఛికం — మీకు OTP అందకపోతే మాత్రమే అవసరం.';

  @override
  String get verificationAadhaarFront => 'Aadhaar ఫ్రంట్';

  @override
  String get verificationAadhaarBack => 'Aadhaar వెనుక';

  @override
  String get verificationCantReceiveOtp =>
      'OTP అందుకోవడం లేదా? పత్రాలతో కొనసాగండి';

  @override
  String get verificationWhyAadhaarTitle =>
      'మేము Aadhaar ధృవీకరణను దీని కోసం ఉపయోగిస్తాము:';

  @override
  String get verificationReviewingDetails =>
      'మా బృందం మీ వివరాలను సమీక్షిస్తోంది. ఆమోదం పొందిన తర్వాత మీ క్రెడిట్ పరిమితి మీ ప్రొఫైల్‌లో కనిపిస్తుంది.';

  @override
  String get verificationCreditReflectionNote =>
      'ఆమోదం పొందిన తర్వాత క్రెడిట్ ప్రతిబింబం జరగడానికి 2–4 గంటల సమయం పట్టవచ్చు.';

  @override
  String get verificationCompleteSelections =>
      'దయచేసి అన్ని ఎంపికలను పూర్తి చేయండి';

  @override
  String get verificationHelpDetermineEligibility =>
      'మీ రుణ అర్హతను నిర్ధారించడంలో మాకు సహాయపడండి.';

  @override
  String get verificationHousehold => 'గృహస్థులు';

  @override
  String get verificationDraftSaved => 'డ్రాఫ్ట్ సేవ్ చేయబడింది';

  @override
  String get verificationInitialAssessment =>
      'ప్రాథమిక ప్రొఫైల్ అంచనా ఆధారంగా.';

  @override
  String get verificationUploadAllDocs =>
      'దయచేసి అవసరమైన అన్ని పత్రాలను అప్‌లోడ్ చేయండి';

  @override
  String get verificationWhyDocumentsTitle =>
      'మేము మీ పత్రాలను వీటి కోసం ఉపయోగిస్తాము:';

  @override
  String get verificationPanConsentRequired =>
      'కొనసాగించడానికి, దయచేసి మీ PAN ధృవీకరించడానికి మాకు అనుమతించండి.';

  @override
  String get verificationPanVerified => 'PAN ధృవీకరించబడింది';

  @override
  String get verificationPanComplianceNote =>
      'ఆర్థిక నిబంధనల పాటింపు కోసం మీ PAN అవసరం.';

  @override
  String get verificationRiskEvaluation => 'ప్రమాద అంచనా';

  @override
  String get verificationPanConsentText =>
      'KYC కోసం నా PAN ఆదాయపు పన్ను శాఖతో ధృవీకరించడానికి VS Mart నేను సమ్మతిస్తున్నాను.';

  @override
  String get verificationVerifyPan => 'PAN ధృవీకరించండి';

  @override
  String get verificationSubmitYourDetails => 'దయచేసి మీ వివరాలను సమర్పించండి.';

  @override
  String get verificationResidencePhotoAttached =>
      'నివాస ఛాయాచిత్రం జతచేయబడింది.';

  @override
  String get verificationCameraGalleryError =>
      'కెమెరా/గ్యాలరీని యాక్సెస్ చేయలేకపోయాను.';

  @override
  String get verificationAddResidencePhoto =>
      'దయచేసి మీ నివాసం యొక్క ఫోటోను జోడించండి.';

  @override
  String get verificationCaptureLocationFirst =>
      'సమర్పించే ముందు మీ స్థానాన్ని నమోదు చేసుకోండి.';

  @override
  String get verificationResidenceSubmitted => 'నివాస ధృవీకరణ సమర్పించబడింది.';

  @override
  String get verificationResidenceIntro =>
      'వేగవంతమైన ప్రాసెసింగ్ మరియు సురక్షితమైన డెలివరీల కోసం, మీ చిరునామాను ధృవీకరించడానికి దయచేసి మీ నివాసం యొక్క స్పష్టమైన ఫోటోను అప్‌లోడ్ చేయండి.';

  @override
  String get verificationSampleApprovedImage => 'నమూనా ఆమోదించబడిన చిత్రం';

  @override
  String get verificationIdeal => 'ఆదర్శం';

  @override
  String get verificationLatitude => 'అక్షాంశం';

  @override
  String get verificationLongitude => 'రేఖాంశం';

  @override
  String get verificationSubmissionFailed =>
      'సమర్పణ విఫలమైంది. దయచేసి మళ్ళీ ప్రయత్నించండి.';

  @override
  String get verificationAddress => 'చిరునామా';

  @override
  String get verificationSelfie => 'సెల్ఫీ';

  @override
  String get verificationCreditInformation => 'క్రెడిట్ సమాచారం';

  @override
  String get verificationHouse => 'ఇల్లు';

  @override
  String get verificationCompleteAllSections =>
      'మీ దరఖాస్తును సమర్పించడానికి అన్ని విభాగాలను పూర్తి చేయండి.';

  @override
  String get verificationApplicationSubmitted => 'దరఖాస్తు సమర్పించబడింది';

  @override
  String get verificationCreditDecision => 'రుణ అర్హత నిర్ణయం';

  @override
  String verificationApplicationRef(Object id) {
    return 'అప్లికేషన్ $id';
  }

  @override
  String get verificationNotifyDecision =>
      'నిర్ణయం తీసుకున్న వెంటనే మేము మీకు తెలియజేస్తాము. ఈలోగా మీరు బ్రౌజింగ్ కొనసాగించవచ్చు.';

  @override
  String verificationUploading(Object title) {
    return '$title అప్‌లోడ్ అవుతోంది…';
  }

  @override
  String get verificationLimitLabel => 'పరిమితి';

  @override
  String get verificationCaptureFailed => 'క్యాప్చర్ విఫలమైంది';

  @override
  String get verificationSelfieCaptured => 'సెల్ఫీ తీయబడింది';
}
