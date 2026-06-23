import '../../domain/entities/cart_item.dart';

/// Serialization model bridging [CartItem] and the JSON maps persisted by
/// `CartStorage` (Hive). Kept plain (no codegen) since the shape is local-only.
abstract final class CartItemModel {
  CartItemModel._();

  static Map<String, dynamic> toJson(CartItem item) => {
        'productId': item.productId,
        'name': item.name,
        'brand': item.brand,
        'unit': item.unit,
        'price': item.price,
        'mrp': item.mrp,
        'quantity': item.quantity,
        'imageUrl': item.imageUrl,
        'variantId': item.variantId,
      };

  static CartItem fromJson(Map<String, dynamic> json) => CartItem(
        productId: json['productId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        brand: json['brand'] as String? ?? '',
        unit: json['unit'] as String? ?? '',
        price: (json['price'] as num?) ?? 0,
        mrp: (json['mrp'] as num?) ?? 0,
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
        imageUrl: json['imageUrl'] as String?,
        variantId: json['variantId'] as String?,
      );
}
