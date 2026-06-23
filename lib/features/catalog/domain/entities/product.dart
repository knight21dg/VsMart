import 'package:equatable/equatable.dart';

import 'product_price.dart';
import 'product_variant.dart';

/// Availability state surfaced on the product detail screen.
enum StockStatus { inStock, lowStock, outOfStock }

/// Core domain representation of a catalog product.
class Product extends Equatable {
  const Product({
    required this.id,
    required this.name,
    required this.brand,
    required this.unit,
    required this.price,
    required this.mrp,
    required this.categoryId,
    this.creditPrice,
    this.rating = 0,
    this.reviews = 0,
    this.imageUrl,
    this.images = const [],
    this.inStock = true,
    this.stockCount,
    this.description,
    this.variants = const [],
    this.specifications = const {},
  });

  final String id;
  final String name;
  final String brand;
  final String unit;
  final num price;
  final num mrp;
  final String categoryId;
  final num? creditPrice;
  final double rating;
  final int reviews;
  final String? imageUrl;
  final List<String> images;
  final bool inStock;

  /// Units in stock when known (drives low/out-of-stock states).
  final int? stockCount;
  final String? description;
  final List<ProductVariant> variants;
  final Map<String, String> specifications;

  /// Structured pricing (selling/MRP/credit + derived discount & savings).
  ProductPrice get pricing =>
      ProductPrice(sellingPrice: price, mrp: mrp, creditPrice: creditPrice);

  /// Availability state derived from [inStock] and [stockCount].
  StockStatus get stockStatus {
    if (!inStock || stockCount == 0) return StockStatus.outOfStock;
    if (stockCount != null && stockCount! <= 5) return StockStatus.lowStock;
    return StockStatus.inStock;
  }

  /// Gallery images, falling back to the single [imageUrl] when none provided.
  List<String> get gallery =>
      images.isNotEmpty ? images : [if (imageUrl != null) imageUrl!];

  int get discountPercent => pricing.discountPercent;
  num get savings => pricing.savings;

  @override
  List<Object?> get props => [
        id,
        name,
        brand,
        unit,
        price,
        mrp,
        categoryId,
        creditPrice,
        rating,
        reviews,
        imageUrl,
        images,
        inStock,
        stockCount,
        description,
        variants,
        specifications,
      ];
}
