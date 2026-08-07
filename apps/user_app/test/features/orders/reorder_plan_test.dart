import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/orders/domain/entities/reorder_line.dart';

/// The reorder preview is the app's only source of truth for what a reorder adds.
/// Both previous implementations got this wrong: one dropped the VARIANT (a 5 kg
/// pack came back as the base SKU), the other rebuilt lines from the order's
/// HISTORICAL prices.
Map<String, dynamic> _line({
  String? productId = '10',
  String? variantId,
  String name = 'Rice',
  num? price = 100,
  num? mrp = 120,
  bool available = true,
  String reason = '',
  int quantity = 2,
}) =>
    {
      'productId': productId,
      'variantId': variantId,
      'name': name,
      'brand': 'VS',
      'unit': '1kg',
      'quantity': quantity,
      'price': price,
      'mrp': mrp,
      'imageUrl': '',
      'available': available,
      'reason': reason,
    };

void main() {
  group('ReorderPlan parsing', () {
    test('splits available from unavailable lines', () {
      final plan = ReorderPlan.fromJson({
        'items': [
          _line(),
          _line(name: 'Dal', available: false, reason: 'out_of_stock'),
        ],
      });

      expect(plan.available, hasLength(1));
      expect(plan.unavailable, hasLength(1));
      expect(plan.hasAnythingToAdd, isTrue);
    });

    test('distinguishes discontinued from out of stock', () {
      final plan = ReorderPlan.fromJson({
        'items': [
          _line(available: false, reason: 'discontinued'),
          _line(name: 'Dal', available: false, reason: 'out_of_stock'),
        ],
      });

      expect(plan.lines[0].reason, ReorderUnavailableReason.discontinued);
      expect(plan.lines[1].reason, ReorderUnavailableReason.outOfStock);
      expect(plan.hasAnythingToAdd, isFalse);
    });

    test('an unknown reason does not crash the sheet', () {
      final plan =
          ReorderPlan.fromJson({'items': [_line(available: false, reason: 'wat')]});
      expect(plan.lines.single.reason, ReorderUnavailableReason.unknown);
    });

    test('an empty payload is an empty plan, not an error', () {
      final plan = ReorderPlan.fromJson({});
      expect(plan.isEmpty, isTrue);
      expect(plan.hasAnythingToAdd, isFalse);
    });

    test('total counts only what will actually be added', () {
      final plan = ReorderPlan.fromJson({
        'items': [
          _line(price: 100, quantity: 2),
          _line(name: 'Dal', price: 500, available: false, reason: 'out_of_stock'),
        ],
      });
      expect(plan.total, 200);
    });
  });

  group('ReorderLine → CartItem', () {
    test('carries the variant so the original pack is restored', () {
      final line = ReorderLine.fromJson(_line(variantId: '55', price: 500));
      expect(line.toCartItem().variantId, '55');
    });

    test('a variantless line stays variantless', () {
      expect(ReorderLine.fromJson(_line()).toCartItem().variantId, isNull);
    });

    test('uses the live price, not whatever was paid last time', () {
      final line = ReorderLine.fromJson(_line(price: 150));
      expect(line.toCartItem().price, 150);
    });

    test('mrp below price is clamped so savings never render negative', () {
      // The server can legitimately return an mrp under the live price after a
      // price rise; the UI must not show a negative discount.
      final line = ReorderLine.fromJson(_line(price: 150, mrp: 120));
      final item = line.toCartItem();
      expect(item.mrp, 150);
      expect(item.mrp - item.price, 0);
    });

    test('a normal mrp above price is preserved', () {
      final item = ReorderLine.fromJson(_line(price: 100, mrp: 120)).toCartItem();
      expect(item.mrp, 120);
    });

    test('quantity is carried across', () {
      expect(ReorderLine.fromJson(_line(quantity: 3)).toCartItem().quantity, 3);
    });
  });
}
