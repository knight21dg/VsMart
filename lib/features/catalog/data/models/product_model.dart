import '../../domain/entities/product.dart';
import '../../domain/entities/product_variant.dart';

/// JSON serialization for [Product] (cache + future remote API), including
/// nested variants, gallery images and specifications.
abstract final class ProductModel {
  ProductModel._();

  static Map<String, dynamic> toJson(Product p) => {
        'id': p.id,
        'name': p.name,
        'brand': p.brand,
        'unit': p.unit,
        'price': p.price,
        'mrp': p.mrp,
        'creditPrice': p.creditPrice,
        'categoryId': p.categoryId,
        'rating': p.rating,
        'reviews': p.reviews,
        'imageUrl': p.imageUrl,
        'images': p.images,
        'inStock': p.inStock,
        'stockCount': p.stockCount,
        'description': p.description,
        'variants': p.variants.map(_variantToJson).toList(),
        'specifications': p.specifications,
      };

  static Product fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        brand: j['brand'] as String? ?? '',
        unit: j['unit'] as String? ?? '',
        price: (j['price'] as num?) ?? 0,
        mrp: (j['mrp'] as num?) ?? 0,
        creditPrice: j['creditPrice'] as num?,
        categoryId: j['categoryId'] as String? ?? '',
        rating: (j['rating'] as num?)?.toDouble() ?? 0,
        reviews: (j['reviews'] as num?)?.toInt() ?? 0,
        imageUrl: j['imageUrl'] as String?,
        images: (j['images'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        inStock: j['inStock'] as bool? ?? true,
        stockCount: (j['stockCount'] as num?)?.toInt(),
        description: j['description'] as String?,
        variants: (j['variants'] as List?)
                ?.whereType<Map>()
                .map((e) => _variantFromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            const [],
        specifications: (j['specifications'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            ) ??
            const {},
      );

  static Map<String, dynamic> _variantToJson(ProductVariant v) => {
        'id': v.id,
        'label': v.label,
        'priceDelta': v.priceDelta,
        'inStock': v.inStock,
      };

  static ProductVariant _variantFromJson(Map<String, dynamic> j) =>
      ProductVariant(
        id: j['id'] as String? ?? '',
        label: j['label'] as String? ?? '',
        priceDelta: (j['priceDelta'] as num?) ?? 0,
        inStock: j['inStock'] as bool? ?? true,
      );
}
