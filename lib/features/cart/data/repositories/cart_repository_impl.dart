import '../../../../core/storage/cart_storage.dart';
import '../../domain/entities/cart.dart';
import '../../domain/entities/cart_item.dart';
import '../../domain/repositories/cart_repository.dart';
import '../models/cart_item_model.dart';

/// [CartRepository] backed by [CartStorage] (Hive). Each mutation reads the
/// current items, applies the change, persists, and returns the new [Cart].
class CartRepositoryImpl implements CartRepository {
  CartRepositoryImpl(this._storage);

  final CartStorage _storage;

  List<CartItem> _read() =>
      _storage.getItems().map(CartItemModel.fromJson).toList();

  Future<Cart> _write(List<CartItem> items) async {
    await _storage.saveItems(items.map(CartItemModel.toJson).toList());
    return Cart(List.unmodifiable(items));
  }

  @override
  Cart getCart() => Cart(List.unmodifiable(_read()));

  @override
  Future<Cart> addItem(CartItem item) async {
    final items = _read();
    final index = items.indexWhere((i) => i.productId == item.productId);
    if (index >= 0) {
      items[index] =
          items[index].copyWith(quantity: items[index].quantity + item.quantity);
    } else {
      items.add(item);
    }
    return _write(items);
  }

  @override
  Future<Cart> setQuantity(String productId, int quantity) async {
    final items = _read();
    final index = items.indexWhere((i) => i.productId == productId);
    if (index < 0) return Cart(List.unmodifiable(items));
    if (quantity <= 0) {
      items.removeAt(index);
    } else {
      items[index] = items[index].copyWith(quantity: quantity);
    }
    return _write(items);
  }

  @override
  Future<Cart> removeItem(String productId) async {
    final items = _read()..removeWhere((i) => i.productId == productId);
    return _write(items);
  }

  @override
  Future<Cart> clear() async {
    await _storage.clear();
    return const Cart.empty();
  }
}
