import 'package:equatable/equatable.dart';

import 'cart_item.dart';

/// The shopping cart aggregate: a set of line items plus derived totals used by
/// the cart, checkout, and credit-eligibility flows.
class Cart extends Equatable {
  const Cart(this.items);

  const Cart.empty() : items = const [];

  final List<CartItem> items;

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => items.isNotEmpty;

  /// Total quantity across all lines (used for badges).
  int get itemCount => items.fold(0, (sum, i) => sum + i.quantity);

  /// Number of distinct products.
  int get lineCount => items.length;

  num get itemTotal => items.fold<num>(0, (sum, i) => sum + i.lineTotal);
  num get mrpTotal => items.fold<num>(0, (sum, i) => sum + i.lineMrp);
  num get savings => mrpTotal > itemTotal ? mrpTotal - itemTotal : 0;

  /// Quantity of a cart LINE, keyed by [CartItem.lineKey].
  ///
  /// For a product without a variant the lineKey IS the productId, so every
  /// existing product-keyed caller (grid cards, rails) is unaffected. Matching
  /// on productId alone returned 0 for a variant line — which made the steppers
  /// read the wrong quantity and reset it to 1.
  int quantityOf(String lineKey) => items
      .firstWhere(
        (i) => i.lineKey == lineKey,
        orElse: () => const CartItem(
          productId: '',
          name: '',
          brand: '',
          unit: '',
          price: 0,
          mrp: 0,
          quantity: 0,
        ),
      )
      .quantity;

  @override
  List<Object?> get props => [items];
}
