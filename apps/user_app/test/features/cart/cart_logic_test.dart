import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/cart/domain/entities/cart_item.dart';
import 'package:user_app/features/cart/presentation/providers/cart_providers.dart';

import '../../helpers/fake_cart_repository.dart';

CartItem _item(String id, {num price = 100, num mrp = 120, int qty = 1}) =>
    CartItem(productId: id, name: 'P$id', brand: 'VS', unit: '1',
        price: price, mrp: mrp, quantity: qty);

/// A container wired with an in-memory cart and the backend bill forced to null,
/// so `cartSummaryProvider` exercises the on-device estimate (offline) path.
ProviderContainer _container({List<CartItem>? items}) {
  final c = ProviderContainer(overrides: [
    cartRepositoryProvider.overrideWithValue(FakeCartRepository(items)),
    cartBillProvider.overrideWith((ref) async => null),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('CartController mutations', () {
    test('add then increment/decrement adjusts quantity', () async {
      final c = _container();
      final ctrl = c.read(cartControllerProvider.notifier);
      await ctrl.add(_item('1'));
      expect(c.read(cartControllerProvider).quantityOf('1'), 1);
      await ctrl.increment('1');
      expect(c.read(cartControllerProvider).quantityOf('1'), 2);
      await ctrl.decrement('1');
      expect(c.read(cartControllerProvider).quantityOf('1'), 1);
    });

    test('decrement to zero removes the line', () async {
      final c = _container(items: [_item('1', qty: 1)]);
      await c.read(cartControllerProvider.notifier).decrement('1');
      expect(c.read(cartControllerProvider).isEmpty, true);
    });

    test('adding the same product increments instead of duplicating', () async {
      final c = _container();
      final ctrl = c.read(cartControllerProvider.notifier);
      await ctrl.add(_item('1'));
      await ctrl.add(_item('1'));
      expect(c.read(cartControllerProvider).lineCount, 1);
      expect(c.read(cartControllerProvider).quantityOf('1'), 2);
    });

    test('clear empties the cart', () async {
      final c = _container(items: [_item('1'), _item('2')]);
      await c.read(cartControllerProvider.notifier).clear();
      expect(c.read(cartControllerProvider).isEmpty, true);
    });
  });

  group('cartSummaryProvider — offline estimate', () {
    test('empty cart → zero totals, flagged as estimate', () {
      final s = _container().read(cartSummaryProvider);
      expect(s.subtotal, 0);
      expect(s.total, 0);
      expect(s.isEstimate, true);
    });

    test('below free-delivery threshold adds the delivery fee', () {
      // subtotal 400 < 499 → delivery 45; gst round(400*0.18)=72; total 517
      final s = _container(items: [_item('1', price: 400, mrp: 400)])
          .read(cartSummaryProvider);
      expect(s.subtotal, 400);
      expect(s.deliveryCharges, 45);
      expect(s.gstAmount, 72);
      expect(s.total, 517);
      expect(s.qualifiesFreeDelivery, false);
    });

    test('at/above threshold → free delivery', () {
      // subtotal 500 >= 499 → delivery 0; gst round(500*0.18)=90; total 590
      final s = _container(items: [_item('1', price: 500, mrp: 500)])
          .read(cartSummaryProvider);
      expect(s.deliveryCharges, 0);
      expect(s.total, 590);
      expect(s.qualifiesFreeDelivery, true);
    });

    test('savings aggregates mrp − price across quantity', () {
      final s = _container(items: [_item('1', price: 100, mrp: 120, qty: 2)])
          .read(cartSummaryProvider);
      expect(s.subtotal, 200);
      expect(s.savings, 40); // (120-100) * 2
    });
  });
}
