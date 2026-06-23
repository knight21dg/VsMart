import '../../app/constants/storage_keys.dart';
import 'hive_service.dart';

/// Persists the cart locally so it survives app restarts and works offline.
///
/// Items are stored as a list of JSON maps; feature code maps them to/from
/// `CartItemModel`.
class CartStorage {
  CartStorage(this._hive);

  final HiveService _hive;

  List<Map<String, dynamic>> getItems() {
    final raw = _hive.cartBox.get(StorageKeys.cartItems);
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  Future<void> saveItems(List<Map<String, dynamic>> items) =>
      _hive.cartBox.put(StorageKeys.cartItems, items);

  Future<void> clear() => _hive.cartBox.delete(StorageKeys.cartItems);
}
