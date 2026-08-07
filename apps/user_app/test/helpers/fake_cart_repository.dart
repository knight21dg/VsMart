import 'package:user_app/features/cart/domain/entities/cart.dart';
import 'package:user_app/features/cart/domain/entities/cart_item.dart';
import 'package:user_app/features/cart/domain/repositories/cart_repository.dart';

/// In-memory [CartRepository] for tests — mirrors the Hive-backed impl's contract
/// (add increments, setQuantity<=0 removes) without touching local storage.
class FakeCartRepository implements CartRepository {
  FakeCartRepository([List<CartItem>? initial]) : _items = [...?initial];

  final List<CartItem> _items;

  @override
  Cart getCart() => Cart(List.unmodifiable(_items));

  @override
  Future<Cart> addItem(CartItem item) async {
    final i = _items.indexWhere((x) => x.productId == item.productId);
    if (i >= 0) {
      _items[i] = _items[i].copyWith(quantity: _items[i].quantity + item.quantity);
    } else {
      _items.add(item);
    }
    return getCart();
  }

  @override
  Future<Cart> setQuantity(String productId, int quantity) async {
    final i = _items.indexWhere((x) => x.productId == productId);
    if (i >= 0) {
      if (quantity <= 0) {
        _items.removeAt(i);
      } else {
        _items[i] = _items[i].copyWith(quantity: quantity);
      }
    }
    return getCart();
  }

  @override
  Future<Cart> removeItem(String productId) async {
    _items.removeWhere((x) => x.productId == productId);
    return getCart();
  }

  @override
  Future<Cart> clear() async {
    _items.clear();
    return getCart();
  }
}
