import 'package:equatable/equatable.dart';

/// A single line in the shopping cart.
class CartItem extends Equatable {
  const CartItem({
    required this.productId,
    required this.name,
    required this.brand,
    required this.unit,
    required this.price,
    required this.mrp,
    required this.quantity,
    this.imageUrl,
    this.variantId,
  });

  final String productId;
  final String name;
  final String brand;
  final String unit;
  final num price;
  final num mrp;
  final int quantity;
  final String? imageUrl;

  /// Selected product variant, when the line refers to a specific variant.
  final String? variantId;

  /// Identity of a cart LINE.
  ///
  /// Two variants of one product are two different sellable things at two
  /// different prices, so they must be two lines. Keying the cart on `productId`
  /// alone silently merged them into whichever was added first — the second
  /// variant's price simply vanished. For a product without a variant this is
  /// just the productId, so every existing product-keyed call still works.
  String get lineKey => variantId == null ? productId : '$productId:$variantId';

  num get lineTotal => price * quantity;
  num get lineMrp => mrp * quantity;
  num get lineSavings => lineMrp > lineTotal ? lineMrp - lineTotal : 0;

  CartItem copyWith({int? quantity}) => CartItem(
        productId: productId,
        name: name,
        brand: brand,
        unit: unit,
        price: price,
        mrp: mrp,
        quantity: quantity ?? this.quantity,
        imageUrl: imageUrl,
        variantId: variantId,
      );

  @override
  List<Object?> get props =>
      [productId, name, brand, unit, price, mrp, quantity, imageUrl, variantId];
}
