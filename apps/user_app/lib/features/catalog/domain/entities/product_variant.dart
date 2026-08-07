import 'package:equatable/equatable.dart';

/// A separately-stocked, separately-priced pack of a product (e.g. 500 g / 1 kg).
///
/// Each variant carries its OWN stock and its own image — a 1 kg being sold out
/// says nothing about the 500 g. [available] is the pack's own sellable count in
/// the serving store (null only for the global catalog, where per-store stock
/// isn't resolved); [inStock] is the honest per-pack flag.
class ProductVariant extends Equatable {
  const ProductVariant({
    required this.id,
    required this.label,
    this.priceDelta = 0,
    this.price,
    this.mrp,
    this.imageUrl,
    this.available,
    this.inStock = true,
  });

  final String id;
  final String label;
  final num priceDelta;

  /// Resolved selling price for this pack (store base + delta), when the backend
  /// provides it. Callers can fall back to base+delta otherwise.
  final num? price;
  final num? mrp;

  /// This pack's own photo. Falls back to the product image when null/blank.
  final String? imageUrl;

  /// This pack's own available count in the serving store (null = unknown/global).
  final int? available;
  final bool inStock;

  bool get isSellable => available != null ? available! > 0 : inStock;

  @override
  List<Object?> get props =>
      [id, label, priceDelta, price, mrp, imageUrl, available, inStock];
}
