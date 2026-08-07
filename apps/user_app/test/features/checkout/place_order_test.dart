import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/app/constants/storage_keys.dart';
import 'package:user_app/core/errors/failures.dart';
import 'package:user_app/features/address/domain/entities/address.dart';
import 'package:user_app/features/address/presentation/providers/address_selection_provider.dart';
import 'package:user_app/features/cart/domain/entities/cart_item.dart';
import 'package:user_app/features/cart/presentation/providers/cart_providers.dart';
import 'package:user_app/features/checkout/presentation/providers/checkout_controller.dart';
import 'package:user_app/features/orders/presentation/providers/order_providers.dart';
import 'package:user_app/features/serviceability/data/serviceability_result.dart';
import 'package:user_app/features/serviceability/presentation/providers/serviceability_providers.dart';
import 'package:user_app/shared/providers/core_providers.dart';

import '../../helpers/fake_cart_repository.dart';
import '../../helpers/fake_checkout_deps.dart';
import '../../helpers/fake_hive_service.dart';

const _item = CartItem(productId: '1', name: 'P', brand: 'VS', unit: '1',
    price: 100, mrp: 100, quantity: 1);

const _address = Address(id: 'a1', name: 'X', phone: '9000000000',
    latitude: 12.97, longitude: 77.6, pincode: '560001');

typedef _Setup = ({
  ProviderContainer container,
  FakeOrderRepository repo,
  FakeHiveService hive,
  CountingAnalytics analytics,
});

_Setup _setup({FakeOrderRepository? repo, bool serviceable = true, bool seedDraft = false}) {
  final r = repo ?? FakeOrderRepository();
  final hive = FakeHiveService();
  if (seedDraft) {
    hive.boxFor(StorageKeys.checkoutDraftBox).put('draft', {'paymentMethod': 'cashOnDelivery'});
  }
  final analytics = CountingAnalytics();
  final container = ProviderContainer(overrides: [
    hiveServiceProvider.overrideWithValue(hive),
    analyticsServiceProvider.overrideWithValue(analytics),
    cartRepositoryProvider.overrideWithValue(FakeCartRepository([_item])),
    cartBillProvider.overrideWith((ref) async => null),
    cartValidationServiceProvider.overrideWithValue(FakeCartValidationService()),
    selectedAddressProvider.overrideWithValue(_address),
    serviceabilityProvider.overrideWith(
        () => FakeServiceabilityController(ServiceabilityResult(serviceable: serviceable))),
    orderRepositoryProvider.overrideWithValue(r),
  ]);
  addTearDown(container.dispose);
  return (container: container, repo: r, hive: hive, analytics: analytics);
}

void main() {
  group('CheckoutController.placeOrder', () {
    test('double-tap → exactly ONE checkout request + one order, analytics once',
        () async {
      final s = _setup();
      final ctrl = s.container.read(checkoutControllerProvider.notifier);
      final results = await Future.wait([ctrl.placeOrder(), ctrl.placeOrder()]);
      expect(s.repo.checkoutCalls, 1); // re-entry never reached the backend
      expect(results.where((o) => o != null).length, 1); // one order, one null
      expect(s.analytics.orderPlaced, 1); // analytics fired exactly once
    });

    test('placing flag is set synchronously and blocks re-entry', () async {
      final s = _setup();
      final ctrl = s.container.read(checkoutControllerProvider.notifier);
      final inFlight = ctrl.placeOrder();
      // Set before the first await, so a second tap in the same frame is blocked.
      expect(s.container.read(checkoutControllerProvider).placing, true);
      expect(await ctrl.placeOrder(), isNull);
      await inFlight;
    });

    test('success clears cart + draft + idempotency key', () async {
      final s = _setup(seedDraft: true);
      final order = await s.container.read(checkoutControllerProvider.notifier).placeOrder();
      expect(order, isNotNull);
      // cart.clear() is fire-and-forget in the controller — let its state settle.
      await Future<void>.delayed(Duration.zero);
      expect(s.container.read(cartControllerProvider).isEmpty, true);
      expect(s.hive.boxFor(StorageKeys.checkoutDraftBox).get('draft'), isNull);
      expect(s.container.read(checkoutControllerProvider).idempotencyKey, isNull);
    });

    test('failure resets placing, KEEPS the draft, and retry reuses the same key',
        () async {
      final s = _setup(
          repo: FakeOrderRepository(failure: const ServerFailure('500')),
          seedDraft: true);
      final ctrl = s.container.read(checkoutControllerProvider.notifier);

      expect(await ctrl.placeOrder(), isNull);
      final state = s.container.read(checkoutControllerProvider);
      expect(state.error, isNotNull);
      expect(state.placing, false); // loading reset after failure
      expect(s.hive.boxFor(StorageKeys.checkoutDraftBox).get('draft'), isNotNull);

      expect(await ctrl.placeOrder(), isNull); // retry (still failing)
      expect(s.repo.checkoutCalls, 2);
      expect(s.repo.idempotencyKeys[0], s.repo.idempotencyKeys[1]); // SAME key
    });

    test('not-serviceable address blocks before any order request', () async {
      final s = _setup(serviceable: false);
      final order = await s.container.read(checkoutControllerProvider.notifier).placeOrder();
      expect(order, isNull);
      expect(s.repo.checkoutCalls, 0); // never hit the backend
      expect(s.container.read(checkoutControllerProvider).error?.code,
          'ADDRESS_NOT_SERVICEABLE');
      expect(s.container.read(checkoutControllerProvider).placing, false);
    });
  });
}
