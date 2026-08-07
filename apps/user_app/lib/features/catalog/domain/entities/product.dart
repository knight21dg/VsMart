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
    this.shareToken,
  });

  final String id;
  /// Unguessable public slug for the shareable link (`/products/<shareToken>`),
  /// so a store-private product can be shared without exposing its numeric id.
  final String? shareToken;
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

  bool get hasVariants => variants.isNotEmpty;

  /// Sellability a LISTING should show. A variant product is buyable only if at
  /// least one pack is sellable — the product-level [inStock] can be true off an
  /// unallocated/base bucket that no pack draws on, which is why the card must not
  /// rely on it alone.
  bool get effectiveInStock =>
      hasVariants ? variants.any((v) => v.isSellable) : stockStatus != StockStatus.outOfStock;

  num _variantPrice(ProductVariant v) => v.price ?? (price + v.priceDelta);
  num _variantMrp(ProductVariant v) => v.mrp ?? mrp;

  /// The pack a card/rail should represent for a variant product: the cheapest
  /// SELLABLE pack (falling back to the cheapest pack when none are sellable), so
  /// the card never shows the base price for something you can only buy as a pack.
  ProductVariant? get displayVariant {
    if (!hasVariants) return null;
    final sellable = variants.where((v) => v.isSellable).toList();
    final pool = sellable.isNotEmpty ? sellable : variants;
    return pool.reduce((a, b) => _variantPrice(a) <= _variantPrice(b) ? a : b);
  }

  /// Price to display on a card — the display pack's price for a variant product,
  /// else the base price.
  num get displayPrice {
    final v = displayVariant;
    return v == null ? price : _variantPrice(v);
  }

  num get displayMrp {
    final v = displayVariant;
    return v == null ? mrp : _variantMrp(v);
  }

  /// Gallery images, falling back to the single [imageUrl] when none provided.
  List<String> get gallery =>
      images.isNotEmpty ? images : [if (imageUrl != null) imageUrl!];

  int get discountPercent => pricing.discountPercent;
  num get savings => pricing.savings;

  @override
  List<Object?> get props => [
        id,
        shareToken,
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
