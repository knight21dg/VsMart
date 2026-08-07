import 'dart:math' as math;

/// Banner geometry — the client half of the placement contract.
///
/// **Mirrors `offers/specs.py::PLACEMENT_SPECS` on the backend.** The server crops
/// and stores every banner at exactly the ratio named here, so a slot must render
/// at the same ratio; otherwise `BoxFit.cover` silently crops the image a second
/// time and marketing's framing is lost.
///
/// If you change a ratio here, change `PLACEMENT_SPECS` in the same commit.
class BannerSpec {
  const BannerSpec({
    required this.placement,
    required this.ratio,
    required this.minHeight,
    required this.maxHeight,
    required this.viewportFraction,
  });

  /// Server placement key (`top`, `middle`, `product_list`, …).
  final String placement;

  /// width / height of the stored image.
  final double ratio;

  /// Clamp bounds so the slot stays sane on very small / very large screens.
  final double minHeight;
  final double maxHeight;

  /// Carousel page width as a fraction of the screen (1.0 = full bleed).
  final double viewportFraction;

  /// Rendered height for a slot [screenWidth] wide.
  ///
  /// [horizontalInset] is the padding *inside* the page (the card is that much
  /// narrower than the viewport slice). Feeding it in keeps the box the true
  /// image ratio — computing height from the uninset width stretches the card
  /// slightly taller than the artwork.
  ///
  /// [fraction] overrides [viewportFraction] for callers that render the slot
  /// outside a carousel (a lone banner spans the full content width).
  double heightFor(
    double screenWidth, {
    double horizontalInset = 0,
    double? fraction,
  }) {
    final cardWidth = math.max(
      1.0,
      screenWidth * (fraction ?? viewportFraction) - horizontalInset,
    );
    return (cardWidth / ratio).clamp(minHeight, maxHeight);
  }

  static const top = BannerSpec(
    placement: 'top',
    ratio: 16 / 10,
    minHeight: 180,
    maxHeight: 320,
    viewportFraction: 0.92,
  );
  static const middle = BannerSpec(
    placement: 'middle',
    ratio: 16 / 9,
    minHeight: 140,
    maxHeight: 220,
    viewportFraction: 0.86,
  );
  static const productList = BannerSpec(
    placement: 'product_list',
    ratio: 16 / 9,
    minHeight: 140,
    maxHeight: 220,
    viewportFraction: 0.92,
  );
  static const productDetail = BannerSpec(
    placement: 'product_detail',
    ratio: 16 / 9,
    minHeight: 140,
    maxHeight: 220,
    viewportFraction: 1.0,
  );
  static const cart = BannerSpec(
    placement: 'cart',
    ratio: 16 / 9,
    minHeight: 120,
    maxHeight: 200,
    viewportFraction: 1.0,
  );
  static const spotlight = BannerSpec(
    placement: 'spotlight',
    ratio: 1,
    minHeight: 96,
    maxHeight: 160,
    viewportFraction: 1.0,
  );

  static const all = <BannerSpec>[
    top,
    middle,
    productList,
    productDetail,
    cart,
    spotlight,
  ];

  /// Spec for a server placement key, defaulting to [top] for unknown values so
  /// a new backend placement degrades to a sane box instead of crashing.
  static BannerSpec forPlacement(String? placement) {
    for (final spec in all) {
      if (spec.placement == placement) return spec;
    }
    return top;
  }
}
