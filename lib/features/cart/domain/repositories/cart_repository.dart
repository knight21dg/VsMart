import '../entities/cart.dart';
import '../entities/cart_item.dart';

/// Cart persistence operations. Backed by local storage (Hive) so the cart
/// survives restarts and works offline; reads are synchronous, mutations return
/// the updated [Cart].
abstract interface class CartRepository {
  /// The current cart from local storage.
  Cart getCart();

  /// Add [item] (or increment its quantity if already present).
  Future<Cart> addItem(CartItem item);

  /// Set an exact quantity for a product; a quantity <= 0 removes the line.
  Future<Cart> setQuantity(String productId, int quantity);

  /// Remove a product entirely.
  Future<Cart> removeItem(String productId);

  /// Empty the cart.
  Future<Cart> clear();
}
