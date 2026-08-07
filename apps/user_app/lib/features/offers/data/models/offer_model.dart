import '../../domain/entities/offer.dart';

/// JSON serialization for [Offer] (stale-while-revalidate cache).
abstract final class OfferModel {
  OfferModel._();

  static Map<String, dynamic> toJson(Offer o) => {
        'id': o.id,
        'title': o.title,
        'type': o.type.name,
        'subtitle': o.subtitle,
        'titleTe': o.titleTe,
        'titleHi': o.titleHi,
        'subtitleTe': o.subtitleTe,
        'subtitleHi': o.subtitleHi,
        'code': o.code,
        'imageUrl': o.imageUrl,
        'image': _imageToJson(o.image),
        'badge': o.badge,
        'discountPercent': o.discountPercent,
        'dealPrice': o.dealPrice,
        'originalPrice': o.originalPrice,
        'productId': o.productId,
        'targetPlacement': o.targetPlacement,
        'categoryId': o.categoryId,
        'subcategoryId': o.subcategoryId,
        'isFallback': o.isFallback,
        'isPinned': o.isPinned,
        'action': o.action.name,
        'payload': o.payload,
      };

  static Offer fromJson(Map<String, dynamic> j) => Offer(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        type: OfferType.values.firstWhere(
          (t) => t.name == j['type'],
          orElse: () => OfferType.banner,
        ),
        subtitle: j['subtitle'] as String? ?? '',
        titleTe: j['titleTe'] as String? ?? '',
        titleHi: j['titleHi'] as String? ?? '',
        subtitleTe: j['subtitleTe'] as String? ?? '',
        subtitleHi: j['subtitleHi'] as String? ?? '',
        code: j['code'] as String?,
        imageUrl: j['imageUrl'] as String?,
        image: _imageFromJson(j['image']),
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
        isPinned: (j['isPinned'] ?? j['is_pinned']) == true,
        action: OfferAction.parse(j['action'] as String?),
        payload: j['payload'] is Map
            ? Map<String, dynamic>.from(j['payload'] as Map)
            : const {},
      );

  // Cached image URLs are already absolute (resolved when first fetched).
  static Map<String, dynamic>? _imageToJson(BannerImage? i) => i == null
      ? null
      : {
          'large': i.large,
          'medium': i.medium,
          'small': i.small,
          'thumb': i.thumb,
          'focusX': i.focusX,
          'focusY': i.focusY,
        };

  static BannerImage? _imageFromJson(dynamic raw) {
    if (raw is! Map) return null;
    return BannerImage(
      large: raw['large'] as String?,
      medium: raw['medium'] as String?,
      small: raw['small'] as String?,
      thumb: raw['thumb'] as String?,
      focusX: (raw['focusX'] as num?)?.toDouble() ?? 0.5,
      focusY: (raw['focusY'] as num?)?.toDouble() ?? 0.5,
    );
  }
}
