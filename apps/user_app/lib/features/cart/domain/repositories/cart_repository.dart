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

  /// Set an exact quantity for a cart LINE (`CartItem.lineKey`); <= 0 removes it.
  /// For a product without a variant the lineKey IS the productId.
  Future<Cart> setQuantity(String lineKey, int quantity);

  /// Remove a product entirely.
  Future<Cart> removeItem(String lineKey);

  /// Empty the cart.
  Future<Cart> clear();
}
