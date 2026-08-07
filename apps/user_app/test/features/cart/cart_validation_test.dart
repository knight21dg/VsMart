import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/cart/data/datasources/cart_bill_data_source.dart';
import 'package:user_app/features/cart/domain/entities/cart.dart';
import 'package:user_app/features/cart/domain/entities/cart_item.dart';
import 'package:user_app/features/cart/domain/services/cart_validation_service.dart';

/// Fake stock checker — the real check now lives in the backend `/cart/validate`;
/// here we only verify the Dart mapping (StockLine → CartIssue) and the per-pack
/// line-key that lets the UI remove the exact variant.
class _FakeChecker implements CartStockChecker {
  _FakeChecker(this.result);
  final CartStockCheck result;
  @override
  Future<CartStockCheck> validate(Cart cart) async => result;
}

CartItem _item({String? variantId, int qty = 1}) => CartItem(
    productId: '1', name: 'P', brand: 'VS', unit: '1',
    price: 100, mrp: 120, quantity: qty, variantId: variantId);

CartValidationService _service(CartStockCheck check) =>
    CartValidationService(_FakeChecker(check));

void main() {
  group('CartValidationService (per-variant, per-store stock check)', () {
    test('out-of-stock line → blocking out-of-stock issue', () async {
      final r = await _service(const CartStockCheck(ok: false, lines: [
        StockLine(productId: '1', variantId: null, name: 'P',
            requested: 1, available: 0, inStock: false),
      ])).validateCart(Cart([_item()]));
      expect(r.hasBlocking, true);
      expect(r.issues.single.type, CartIssueType.outOfStock);
    });

    test('requested more than available → blocking quantity issue', () async {
      final r = await _service(const CartStockCheck(ok: false, lines: [
        StockLine(productId: '1', variantId: null, name: 'P',
            requested: 5, available: 2, inStock: false),
      ])).validateCart(Cart([_item(qty: 5)]));
      expect(r.hasBlocking, true);
      expect(r.issues.single.type, CartIssueType.quantityExceedsStock);
    });

    test('a sold-out PACK yields an issue keyed to that variant line', () async {
      final r = await _service(const CartStockCheck(ok: false, lines: [
        StockLine(productId: '1', variantId: '9', name: 'P · 1kg',
            requested: 1, available: 0, inStock: false),
      ])).validateCart(Cart([_item(variantId: '9')]));
      expect(r.hasBlocking, true);
      // The exact pack line (productId:variantId) so the UI removes only it.
      expect(r.issues.single.lineKey, '1:9');
    });

    test('all in stock → no issues', () async {
      final r = await _service(const CartStockCheck(ok: true, lines: [
        StockLine(productId: '1', variantId: null, name: 'P',
            requested: 1, available: 50, inStock: true),
      ])).validateCart(Cart([_item()]));
      expect(r.valid, true);
    });
  });
}
