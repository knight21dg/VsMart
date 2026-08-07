import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/cart/domain/entities/cart.dart';
import 'package:user_app/features/cart/presentation/providers/cart_providers.dart';
import 'package:user_app/features/catalog/domain/entities/product.dart';
import 'package:user_app/features/catalog/domain/entities/product_variant.dart';

/// Regression tests for the variant→cart money bug: the detail screen showed
/// base+priceDelta while the cart silently charged the base price, and two
/// variants of one product collapsed into a single line.
void main() {
  const product = Product(
    id: 'p1', name: 'Tea', brand: 'Tata', unit: '250g',
    price: 100, mrp: 120, categoryId: 'c1',
  );
  const small = ProductVariant(id: 'v1', label: '250 g', priceDelta: 0);
  const large = ProductVariant(id: 'v2', label: '1 kg', priceDelta: 40);

  test('a variant line is charged base + priceDelta, not the base price', () {
    final line = cartItemFrom(product, variant: large);
    expect(line.price, 140);            // was 100 — the bug
    expect(line.mrp, 160);
    expect(line.variantId, 'v2');
    expect(line.name, contains('1 kg'));
  });

  test('no variant => base price and productId as the line key', () {
    final line = cartItemFrom(product);
    expect(line.price, 100);
    expect(line.variantId, isNull);
    expect(line.lineKey, 'p1');         // back-compat for product-keyed callers
  });

  test('two variants of one product are two distinct lines', () {
    final a = cartItemFrom(product, variant: small);
    final b = cartItemFrom(product, variant: large);
    expect(a.lineKey, isNot(b.lineKey));
    expect(Cart([a, b]).lineCount, 2);
    // Total must reflect BOTH prices, not one merged line.
    expect(Cart([a, b]).itemTotal, 240);
  });

  test('quantityOf resolves a variant line by its key', () {
    final cart = Cart([cartItemFrom(product, variant: large, quantity: 3)]);
    expect(cart.quantityOf('p1:v2'), 3);
    expect(cart.quantityOf('p1'), 0);   // the base line does not exist
  });
}
