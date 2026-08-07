import 'package:equatable/equatable.dart';

import '../../data/datasources/cart_bill_data_source.dart';
import '../entities/cart.dart';

/// Kinds of cart problems surfaced before checkout.
enum CartIssueType { outOfStock, quantityExceedsStock, priceChanged }

/// A single validation problem against a cart line.
class CartIssue extends Equatable {
  const CartIssue({
    required this.productId,
    this.variantId,
    required this.name,
    required this.type,
    required this.message,
  });

  final String productId;
  final String? variantId;
  final String name;
  final CartIssueType type;
  final String message;

  /// The cart line this issue targets (matches `CartItem.lineKey`), so the exact
  /// pack can be removed — not every line of the product.
  String get lineKey => variantId == null ? productId : '$productId:$variantId';

  /// Blocks checkout (stock problems); price changes are advisory.
  bool get isBlocking => type != CartIssueType.priceChanged;

  @override
  List<Object?> get props => [productId, variantId, name, type, message];
}

/// Result of validating a cart.
class CartValidationResult extends Equatable {
  const CartValidationResult(this.issues);

  final List<CartIssue> issues;

  bool get valid => issues.isEmpty;
  bool get hasBlocking => issues.any((i) => i.isBlocking);

  @override
  List<Object?> get props => [issues];
}

/// Validates cart lines against live stock before checkout, PER VARIANT and at the
/// customer's serving store. This is the source of truth for "is my cart buyable":
/// the old version checked product-level stock only, so an out-of-stock *pack* of an
/// otherwise in-stock product sailed through to a late failure at Pay. It now defers
/// to the backend `/cart/validate`, which resolves the exact bucket each line draws
/// from.
class CartValidationService {
  CartValidationService(this._stock);

  final CartStockChecker _stock;

  Future<CartValidationResult> validateCart(Cart cart) async {
    if (cart.items.isEmpty) return const CartValidationResult([]);
    try {
      final check = await _stock.validate(cart);
      final issues = <CartIssue>[];
      for (final line in check.lines) {
        if (line.inStock) continue;
        final avail = line.available;
        final partial = avail != null && avail > 0;
        issues.add(CartIssue(
          productId: line.productId,
          variantId: line.variantId,
          name: line.name,
          type: partial
              ? CartIssueType.quantityExceedsStock
              : CartIssueType.outOfStock,
          message: partial
              ? 'Only $avail of ${line.name} left'
              : '${line.name} is out of stock',
        ));
      }
      return CartValidationResult(issues);
    } catch (_) {
      // Network hiccup → don't hard-block here; the stock reserve at Pay is the
      // authoritative final guard and rejects a short line server-side.
      return const CartValidationResult([]);
    }
  }

  Future<bool> canCheckout(Cart cart) async =>
      !(await validateCart(cart)).hasBlocking;
}
