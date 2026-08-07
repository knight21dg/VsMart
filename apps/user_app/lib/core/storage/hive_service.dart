import 'package:hive_flutter/hive_flutter.dart';

import '../../app/constants/storage_keys.dart';

/// Owns Hive initialization and box lifecycle for the app.
///
/// Boxes are opened lazily-once at startup ([init]) and accessed by name.
class HiveService {
  HiveService._();
  static final HiveService instance = HiveService._();

  bool _initialized = false;

  /// Open Hive and all app boxes. Call once during bootstrap, before runApp.
  Future<void> init() async {
    if (_initialized) return;
    await Hive.initFlutter();

    // Register type adapters here as models gain @HiveType annotations, e.g.:
    // Hive.registerAdapter(UserModelAdapter());

    await Future.wait([
      Hive.openBox<dynamic>(StorageKeys.userBox),
      Hive.openBox<dynamic>(StorageKeys.cartBox),
      Hive.openBox<dynamic>(StorageKeys.cacheBox),
      Hive.openBox<dynamic>(StorageKeys.settingsBox),
      Hive.openBox<dynamic>(StorageKeys.verificationBox),
      Hive.openBox<dynamic>(StorageKeys.addressBox),
      Hive.openBox<dynamic>(StorageKeys.categoryBox),
      Hive.openBox<dynamic>(StorageKeys.subCategoryBox),
      Hive.openBox<dynamic>(StorageKeys.productBox),
      Hive.openBox<dynamic>(StorageKeys.offerBox),
      Hive.openBox<dynamic>(StorageKeys.recentlyViewedBox),
      Hive.openBox<dynamic>(StorageKeys.orderBox),
      Hive.openBox<dynamic>(StorageKeys.orderDraftBox),
      Hive.openBox<dynamic>(StorageKeys.trackingBox),
      Hive.openBox<dynamic>(StorageKeys.checkoutDraftBox),
      Hive.openBox<dynamic>(StorageKeys.creditLedgerBox),
      Hive.openBox<dynamic>(StorageKeys.billingCycleBox),
      Hive.openBox<dynamic>(StorageKeys.statementBox),
      Hive.openBox<dynamic>(StorageKeys.invoiceBox),
      Hive.openBox<dynamic>(StorageKeys.paymentHistoryBox),
      Hive.openBox<dynamic>(StorageKeys.collectionBox),
      Hive.openBox<dynamic>(StorageKeys.wishlistBox),
    ]);
    _initialized = true;
  }

  Box<dynamic> box(String name) => Hive.box<dynamic>(name);

  Box<dynamic> get userBox => box(StorageKeys.userBox);
  Box<dynamic> get cartBox => box(StorageKeys.cartBox);
  Box<dynamic> get cacheBox => box(StorageKeys.cacheBox);
  Box<dynamic> get settingsBox => box(StorageKeys.settingsBox);
  Box<dynamic> get verificationBox => box(StorageKeys.verificationBox);
  Box<dynamic> get addressBox => box(StorageKeys.addressBox);
  Box<dynamic> get recentlyViewedBox => box(StorageKeys.recentlyViewedBox);
  Box<dynamic> get orderBox => box(StorageKeys.orderBox);

  /// Wipe every user-scoped box on logout so no data leaks to the next account on
  /// this device. `settingsBox` is intentionally preserved — it holds device
  /// preferences (theme, locale, onboarding-seen), not user data.
  Future<void> clearAll() async {
    const userScoped = [
      StorageKeys.userBox,
      StorageKeys.cartBox,
      StorageKeys.cacheBox,
      StorageKeys.verificationBox,
      StorageKeys.addressBox,
      StorageKeys.categoryBox,
      StorageKeys.subCategoryBox,
      StorageKeys.productBox,
      StorageKeys.offerBox,
      StorageKeys.recentlyViewedBox,
      StorageKeys.orderBox,
      StorageKeys.orderDraftBox,
      StorageKeys.trackingBox,
      StorageKeys.checkoutDraftBox,
      StorageKeys.creditLedgerBox,
      StorageKeys.billingCycleBox,
      StorageKeys.statementBox,
      StorageKeys.invoiceBox,
      StorageKeys.paymentHistoryBox,
      StorageKeys.collectionBox,
      StorageKeys.wishlistBox,
    ];
    await Future.wait([
      for (final name in userScoped)
        if (Hive.isBoxOpen(name)) box(name).clear(),
    ]);
    // Drop user-scoped keys from the shared settings box (keep device prefs).
    final settings = settingsBox;
    for (final key in ['recent_searches', 'recentSearches']) {
      await settings.delete(key);
    }
  }
}
