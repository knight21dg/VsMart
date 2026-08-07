import 'package:equatable/equatable.dart';

/// Kind of promotion, controlling how an [Offer] is rendered.
enum OfferType { banner, deal, coupon }

/// Where a banner renders. Mirrors `offers.Offer.Placement` on the backend.
enum BannerPlacement {
  top('top'),
  middle('middle'),
  spotlight('spotlight'),
  productList('product_list'),
  productDetail('product_detail'),
  cart('cart');

  const BannerPlacement(this.wire);

  /// The server-side key (snake_case), which is *not* the Dart enum name.
  final String wire;

  static BannerPlacement parse(String? v) => BannerPlacement.values.firstWhere(
        (p) => p.wire == v,
        orElse: () => BannerPlacement.top,
      );
}

/// How overlay copy is painted over the artwork. Mirrors `Offer.TextTheme`.
enum BannerTextTheme {
  light,
  dark,
  none;

  static BannerTextTheme parse(String? v) => BannerTextTheme.values.firstWhere(
        (t) => t.name == v,
        orElse: () => BannerTextTheme.light,
      );
}

/// Where the overlay block sits inside the banner. Mirrors `Offer.TextPosition`.
enum BannerTextPosition {
  bottomLeft('bottom_left'),
  bottomCenter('bottom_center'),
  center('center'),
  topLeft('top_left');

  const BannerTextPosition(this.wire);

  final String wire;

  static BannerTextPosition parse(String? v) =>
      BannerTextPosition.values.firstWhere(
        (p) => p.wire == v,
        orElse: () => BannerTextPosition.bottomLeft,
      );
}

/// Deep-link action a banner tap performs. Mirrors `offers.Offer.Action` on the
/// backend; the app branches on this enum instead of parsing URLs.
enum OfferAction {
  none, home, category, product, brand, search,
  credit, offers, cart, profile, order, store, external;

  static OfferAction parse(String? v) => OfferAction.values.firstWhere(
        (a) => a.name == v,
        orElse: () => OfferAction.none,
      );
}

/// Generated WebP size variants for a banner image (absolute URLs), plus the
/// focal point (0..1) used to keep the subject centred when cropping.
class BannerImage extends Equatable {
  const BannerImage({
    this.large, this.medium, this.small, this.thumb,
    this.focusX = 0.5, this.focusY = 0.5,
  });

  final String? large;
  final String? medium;
  final String? small;
  final String? thumb;
  final double focusX;
  final double focusY;

  /// Pick the smallest variant that still covers [logicalWidth] at [dpr]
  /// (DPR-aware) — avoids pulling the 2400px image onto a phone needlessly.
  String? best(double logicalWidth, double dpr) {
    final px = logicalWidth * dpr;
    if (px > 1200 && large != null) return large;
    if (px > 720 && medium != null) return medium;
    return small ?? medium ?? large ?? thumb;
  }

  @override
  List<Object?> get props => [large, medium, small, thumb, focusX, focusY];
}

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
    this.image,
    this.badge,
    this.discountPercent,
    this.dealPrice,
    this.originalPrice,
    this.productId,
    this.targetPlacement,
    this.categoryId,
    this.subcategoryId,
    this.isFallback = false,
    this.titleTe = '',
    this.titleHi = '',
    this.subtitleTe = '',
    this.subtitleHi = '',
    this.action = OfferAction.none,
    this.payload = const {},
    this.isPinned = false,
    this.ctaText = '',
    this.ctaTextTe = '',
    this.ctaTextHi = '',
    this.textTheme = BannerTextTheme.light,
    this.textPosition = BannerTextPosition.bottomLeft,
    this.accentColor,
  });

  final String id;
  final String title;
  final OfferType type;

  /// Banner placement on Home (only meaningful when [type] is banner).
  final BannerPlacement placement;
  final String subtitle;
  final String? code;

  /// Legacy pasted image URL (older banners). Prefer [image] when present.
  final String? imageUrl;

  /// Processed image (WebP size variants + focal point). Null for legacy banners.
  final BannerImage? image;

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

  // ── Localized overlay text (Telugu / Hindi; [title]/[subtitle] are English) ──
  final String titleTe;
  final String titleHi;
  final String subtitleTe;
  final String subtitleHi;

  // ── Deep link ──
  final OfferAction action;
  final Map<String, dynamic> payload;

  /// Pinned banners sort above others in their placement.
  final bool isPinned;

  // ── Overlay presentation ──

  /// Call-to-action pill label. Empty means no button is drawn.
  final String ctaText;
  final String ctaTextTe;
  final String ctaTextHi;

  /// How the copy is painted; [BannerTextTheme.none] suppresses the whole
  /// overlay (scrim included) for artwork that already carries its own copy.
  final BannerTextTheme textTheme;
  final BannerTextPosition textPosition;

  /// `#RRGGBB` accent for the CTA pill and badge; null falls back to brand green.
  final String? accentColor;

  /// CTA label in the given [lang] code ('te'/'hi'), falling back to English.
  String localizedCta(String lang) => switch (lang) {
        'te' => ctaTextTe.isNotEmpty ? ctaTextTe : ctaText,
        'hi' => ctaTextHi.isNotEmpty ? ctaTextHi : ctaText,
        _ => ctaText,
      };

  /// [accentColor] parsed to an ARGB int, or null when unset/malformed.
  int? get accentArgb {
    final hex = accentColor?.replaceFirst('#', '');
    if (hex == null || hex.length != 6) return null;
    return int.tryParse('FF$hex', radix: 16);
  }

  num get savings => (originalPrice != null && dealPrice != null)
      ? (originalPrice! - dealPrice!)
      : 0;

  /// Title in the given [lang] code ('te'/'hi'), falling back to English.
  String localizedTitle(String lang) => switch (lang) {
        'te' => titleTe.isNotEmpty ? titleTe : title,
        'hi' => titleHi.isNotEmpty ? titleHi : title,
        _ => title,
      };

  /// Subtitle in the given [lang] code ('te'/'hi'), falling back to English.
  String localizedSubtitle(String lang) => switch (lang) {
        'te' => subtitleTe.isNotEmpty ? subtitleTe : subtitle,
        'hi' => subtitleHi.isNotEmpty ? subtitleHi : subtitle,
        _ => subtitle,
      };

  @override
  List<Object?> get props => [
        id,
        title,
        type,
        placement,
        subtitle,
        code,
        imageUrl,
        image,
        badge,
        discountPercent,
        dealPrice,
        originalPrice,
        productId,
        targetPlacement,
        categoryId,
        subcategoryId,
        isFallback,
        titleTe,
        titleHi,
        subtitleTe,
        subtitleHi,
        action,
        payload,
        isPinned,
        ctaText,
        ctaTextTe,
        ctaTextHi,
        textTheme,
        textPosition,
        accentColor,
      ];
}
