import 'package:equatable/equatable.dart';

/// A selectable product variant (e.g. pack size, weight) with an optional price
/// delta relative to the product's base price.
class ProductVariant extends Equatable {
  const ProductVariant({
    required this.id,
    required this.label,
    this.priceDelta = 0,
    this.inStock = true,
  });

  final String id;
  final String label;
  final num priceDelta;
  final bool inStock;

  @override
  List<Object?> get props => [id, label, priceDelta, inStock];
}
