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
