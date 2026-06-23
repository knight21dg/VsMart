import 'package:equatable/equatable.dart';

/// Kind of promotion, controlling how an [Offer] is rendered.
enum OfferType { banner, deal, coupon }

/// Where a banner renders on Home.
enum BannerPlacement { top, middle, spotlight }

/// A promotional offer: a home banner, a time-boxed deal, or a coupon.
class Offer extends Equatable {
  const Offer({
    required this.id,
    required this.title,
    required this.type,
    this.placement = BannerPlacement.top,
    this.subtitle = '',
    this.code,
    this.imageUrl,
    this.badge,
    this.discountPercent,
    this.dealPrice,
    this.originalPrice,
    this.productId,
    this.targetPlacement,
    this.categoryId,
    this.subcategoryId,
    this.isFallback = false,
  });

  final String id;
  final String title;
  final OfferType type;

  /// Banner placement on Home (only meaningful when [type] is banner).
  final BannerPlacement placement;
  final String subtitle;
  final String? code;
  final String? imageUrl;
  final String? badge;
  final int? discountPercent;
  final num? dealPrice;
  final num? originalPrice;

  /// Product this offer links to (deals / spotlight banners), if any.
  final String? productId;

  /// Server-side targeting placement string (e.g. `product_list`,
  /// `product_detail`). Null for legacy/home banners.
  final String? targetPlacement;

  /// Category this banner is targeted at, when server-targeted.
  final String? categoryId;

  /// Sub-category this banner is targeted at, when server-targeted.
  final String? subcategoryId;

  /// Whether this is a generic marketing fallback (no specific target match).
  final bool isFallback;

  num get savings => (originalPrice != null && dealPrice != null)
      ? (originalPrice! - dealPrice!)
      : 0;

  @override
  List<Object?> get props => [
        id,
        title,
        type,
        placement,
        subtitle,
        code,
        imageUrl,
        badge,
        discountPercent,
        dealPrice,
        originalPrice,
        productId,
        targetPlacement,
        categoryId,
        subcategoryId,
        isFallback,
      ];
}
