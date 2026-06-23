import 'package:equatable/equatable.dart';

import '../../../catalog/domain/entities/product.dart';
import '../../../catalog/domain/repositories/catalog_repository.dart';
import '../entities/cart.dart';
import '../entities/cart_item.dart';

/// Kinds of cart problems surfaced before checkout.
enum CartIssueType { outOfStock, quantityExceedsStock, priceChanged }

/// A single validation problem against a cart line.
class CartIssue extends Equatable {
  const CartIssue({
    required this.productId,
    required this.name,
    required this.type,
    required this.message,
  });

  final String productId;
  final String name;
  final CartIssueType type;
  final String message;

  /// Blocks checkout (stock problems); price changes are advisory.
  bool get isBlocking => type != CartIssueType.priceChanged;

  @override
  List<Object?> get props => [productId, name, type, message];
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

/// Validates cart lines against live catalog data (stock, quantity, price)
/// before checkout, preventing downstream order failures.
class CartValidationService {
  CartValidationService(this._catalog);

  final CatalogRepository _catalog;

  Future<CartValidationResult> validateCart(Cart cart) async {
    final issues = <CartIssue>[];
    for (final item in cart.items) {
      final issue = await validateItem(item);
      if (issue != null) issues.add(issue);
    }
    return CartValidationResult(issues);
  }

  Future<CartIssue?> validateItem(CartItem item) async {
    final result = await _catalog.getProductById(item.productId);
    return result.fold((_) => null, (product) {
      if (product.stockStatus == StockStatus.outOfStock) {
        return CartIssue(
          productId: item.productId,
          name: item.name,
          type: CartIssueType.outOfStock,
          message: '${item.name} is out of stock',
        );
      }
      final stock = product.stockCount;
      if (stock != null && item.quantity > stock) {
        return CartIssue(
          productId: item.productId,
          name: item.name,
          type: CartIssueType.quantityExceedsStock,
          message: 'Only $stock of ${item.name} left',
        );
      }
      if (product.price != item.price) {
        return CartIssue(
          productId: item.productId,
          name: item.name,
          type: CartIssueType.priceChanged,
          message: 'Price of ${item.name} has changed',
        );
      }
      return null;
    });
  }

  Future<bool> canCheckout(Cart cart) async =>
      !(await validateCart(cart)).hasBlocking;
}
