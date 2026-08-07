import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/app/constants/storage_keys.dart';
import 'package:user_app/features/cart/domain/entities/cart_item.dart';
import 'package:user_app/features/cart/presentation/providers/cart_providers.dart';
import 'package:user_app/features/checkout/presentation/providers/checkout_controller.dart';
import 'package:user_app/features/orders/domain/entities/order_enums.dart';
import 'package:user_app/shared/providers/core_providers.dart';

import '../../helpers/fake_cart_repository.dart';
import '../../helpers/fake_hive_service.dart';

CartItem _item(num price) => CartItem(
    productId: '1', name: 'P', brand: 'VS', unit: '1',
    price: price, mrp: price, quantity: 1);

/// Container with an in-memory cart + Hive, backend bill forced off. `draft`
/// pre-seeds the persisted checkout draft the controller loads on build.
({ProviderContainer container, FakeHiveService hive}) _setup({
  num? cartPrice,
  Map<String, dynamic>? draft,
}) {
  final hive = FakeHiveService();
  if (draft != null) {
    hive.boxFor(StorageKeys.checkoutDraftBox).put('draft', draft);
  }
  final container = ProviderContainer(overrides: [
    hiveServiceProvider.overrideWithValue(hive),
    cartRepositoryProvider.overrideWithValue(
        FakeCartRepository(cartPrice == null ? null : [_item(cartPrice)])),
    cartBillProvider.overrideWith((ref) async => null),
  ]);
  addTearDown(container.dispose);
  return (container: container, hive: hive);
}

void main() {
  group('CheckoutController', () {
    test('loads the persisted draft (payment method + coupon discount)', () {
      final s = _setup(draft: {'paymentMethod': 'upi', 'couponDiscount': 50});
      final state = s.container.read(checkoutControllerProvider);
      expect(state.paymentMethod, PaymentMethod.upi);
      expect(state.couponDiscount, 50);
    });

    test('grandTotal subtracts the coupon discount from the bill', () {
      // cart 500 → estimate total 590 (500 + 0 delivery + 90 gst); discount 50 → 540
      final s = _setup(cartPrice: 500, draft: {'couponDiscount': 50});
      expect(s.container.read(checkoutControllerProvider.notifier).grandTotal(), 540);
    });

    test('grandTotal clamps at zero when discount exceeds the bill', () {
      final s = _setup(cartPrice: 100, draft: {'couponDiscount': 99999});
      expect(s.container.read(checkoutControllerProvider.notifier).grandTotal(), 0);
    });

    test('selectPaymentMethod updates state and persists to the draft', () {
      final s = _setup();
      s.container
          .read(checkoutControllerProvider.notifier)
          .selectPaymentMethod(PaymentMethod.card);
      expect(s.container.read(checkoutControllerProvider).paymentMethod,
          PaymentMethod.card);
      final saved = s.hive.boxFor(StorageKeys.checkoutDraftBox).get('draft') as Map;
      expect(saved['paymentMethod'], 'card');
    });

    test('removeCoupon clears the discount', () {
      final s = _setup(draft: {'coupon': 'SAVE50', 'couponDiscount': 50});
      final ctrl = s.container.read(checkoutControllerProvider.notifier);
      expect(s.container.read(checkoutControllerProvider).couponDiscount, 50);
      ctrl.removeCoupon();
      expect(s.container.read(checkoutControllerProvider).couponDiscount, 0);
      expect(s.container.read(checkoutControllerProvider).coupon, isNull);
    });
  });
}
