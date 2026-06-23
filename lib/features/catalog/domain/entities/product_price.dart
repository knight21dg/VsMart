import 'package:equatable/equatable.dart';

/// Pricing for a product: selling price, MRP, and an optional credit price.
/// Centralizes discount/savings math so the UI never recomputes it.
class ProductPrice extends Equatable {
  const ProductPrice({
    required this.sellingPrice,
    required this.mrp,
    this.creditPrice,
  });

  final num sellingPrice;
  final num mrp;

  /// Price when purchased on VS Credit (defaults to [sellingPrice]).
  final num? creditPrice;

  num get effectiveCreditPrice => creditPrice ?? sellingPrice;

  num get savings => mrp > sellingPrice ? mrp - sellingPrice : 0;

  bool get hasDiscount => discountPercent > 0;

  int get discountPercent {
    if (mrp <= 0 || sellingPrice >= mrp) return 0;
    return (((mrp - sellingPrice) / mrp) * 100).round();
  }

  @override
  List<Object?> get props => [sellingPrice, mrp, creditPrice];
}
