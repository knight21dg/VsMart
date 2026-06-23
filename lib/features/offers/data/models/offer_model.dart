import '../../domain/entities/offer.dart';

/// JSON serialization for [Offer] (cache + future remote API).
abstract final class OfferModel {
  OfferModel._();

  static Map<String, dynamic> toJson(Offer o) => {
        'id': o.id,
        'title': o.title,
        'type': o.type.name,
        'subtitle': o.subtitle,
        'code': o.code,
        'imageUrl': o.imageUrl,
        'badge': o.badge,
        'discountPercent': o.discountPercent,
        'dealPrice': o.dealPrice,
        'originalPrice': o.originalPrice,
        'productId': o.productId,
        'targetPlacement': o.targetPlacement,
        'categoryId': o.categoryId,
        'subcategoryId': o.subcategoryId,
        'isFallback': o.isFallback,
      };

  static Offer fromJson(Map<String, dynamic> j) => Offer(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        type: OfferType.values.firstWhere(
          (t) => t.name == j['type'],
          orElse: () => OfferType.banner,
        ),
        subtitle: j['subtitle'] as String? ?? '',
        code: j['code'] as String?,
        imageUrl: j['imageUrl'] as String?,
        badge: j['badge'] as String?,
        discountPercent: (j['discountPercent'] as num?)?.toInt(),
        dealPrice: j['dealPrice'] as num?,
        originalPrice: j['originalPrice'] as num?,
        productId: j['productId'] as String?,
        targetPlacement:
            (j['targetPlacement'] ?? j['placement'])?.toString(),
        categoryId: (j['categoryId'] ?? j['category_id'])?.toString(),
        subcategoryId:
            (j['subcategoryId'] ?? j['subcategory_id'])?.toString(),
        isFallback: (j['isFallback'] ?? j['is_fallback']) == true,
      );
}
