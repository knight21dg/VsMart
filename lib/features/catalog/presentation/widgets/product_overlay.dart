import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../cart/presentation/providers/cart_providers.dart';
import '../../../reviews/presentation/widgets/product_reviews_section.dart';
import '../../../wishlist/presentation/providers/wishlist_providers.dart';
import '../../domain/entities/product.dart';
import '../providers/product_detail_controller.dart';
import 'product_detail_widgets.dart';
import 'vs_price_widget.dart';
import 'vs_product_gallery.dart';

const double _kRest = 0.82; // resting (floating) height fraction
const double _kMin = 0.5; // drag below → close
const double _kCloseAt = 0.62; // extent under which we pop
const double _kFullAt = 0.985; // at/above this we're a full product page
const double _kRailHeight = 92.0; // floating dock visual height
const double _kRailGap = 12.0; // gap between sticky cart bar and the dock

/// Hero tag pairing a grid product card's image with its overlay card image,
/// so opening/closing morphs between them. Shared by VSProductCard (the grid).
String productHeroTag(String productId) => 'ovl-product-$productId';

/// VS Mart product experience — a floating sheet that rises ~84% over the
/// (visible, blurred) category listing, then expands into a full product page
/// as you pull/scroll up — one continuous surface, no route push. Products are
/// real cards that slide horizontally; the bottom circular wheel is a visual
/// navigator only.
Future<void> showProductOverlay(
  BuildContext context, {
  required List<Product> products,
  required int initialIndex,
}) {
  if (products.isEmpty) return Future<void>.value();
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, __, ___) => _ProductOverlay(
        products: products,
        initialIndex: initialIndex.clamp(0, products.length - 1),
      ),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: child,
      ),
    ),
  );
}

class _ProductOverlay extends StatefulWidget {
  const _ProductOverlay({required this.products, required this.initialIndex});

  final List<Product> products;
  final int initialIndex;

  @override
  State<_ProductOverlay> createState() => _ProductOverlayState();
}

class _ProductOverlayState extends State<_ProductOverlay> {
  final _sheet = DraggableScrollableController();
  late final PageController _page =
      PageController(initialPage: widget.initialIndex);
  // Draggable circular dock pager spanning the full device width (smaller
  // viewportFraction → more thumbnails fill the row, edge to edge).
  late final PageController _dock =
      PageController(initialPage: widget.initialIndex, viewportFraction: 0.15);
  final Map<int, ScrollController> _local = {};
  late int _index = widget.initialIndex;
  double _extent = _kRest;
  bool _detached = false; // during a page hand-off no card holds the sheet ctrl
  bool _closing = false;

  bool get _isFull => _extent >= _kFullAt;

  @override
  void dispose() {
    _sheet.dispose();
    _page.dispose();
    _dock.dispose();
    for (final c in _local.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// The active card scrolls the sheet (drives expand/collapse); the rest use
  /// their own controller. During a hand-off everything is local for one frame
  /// so the sheet controller is never attached to two cards at once.
  ScrollController _controllerFor(int i, ScrollController sheetScroll) {
    if (i == _index && !_detached) return sheetScroll;
    return _local.putIfAbsent(i, () => ScrollController());
  }

  /// Switch the active product. Does the deferred scroll-controller hand-off so
  /// the sheet controller is never attached to two cards at once.
  void _changeTo(int i) {
    if (i == _index) return;
    setState(() => _detached = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _index = i;
        _detached = false;
      });
    });
    HapticFeedback.selectionClick();
  }

  // Two-way sync between the content pager and the draggable dock. Each animates
  // the OTHER to match; the `round() != i` checks stop a feedback loop.
  void _onContentChanged(int i) {
    if (i == _index) return;
    _changeTo(i);
    if (_dock.hasClients && (_dock.page?.round() ?? _index) != i) {
      _dock.animateToPage(i,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic);
    }
  }

  void _onDockChanged(int i) {
    if (i == _index) return;
    _changeTo(i);
    if (_page.hasClients && (_page.page?.round() ?? _index) != i) {
      _page.animateToPage(i,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic);
    }
  }

  void _selectFromRail(int i) {
    if (i == _index || _isFull) return;
    _changeTo(i);
    if (_dock.hasClients) {
      _dock.animateToPage(i,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic);
    }
    if (_page.hasClients) {
      _page.animateToPage(i,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic);
    }
  }

  bool _onNotification(DraggableScrollableNotification n) {
    if (n.extent != _extent) setState(() => _extent = n.extent);
    if (n.extent < _kCloseAt && !_closing) {
      _closing = true;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => Navigator.of(context).maybePop());
    }
    return false;
  }

  void _collapseOrClose() {
    if (_extent > _kRest + 0.04) {
      _sheet.animateTo(_kRest,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 0 at rest → 1 at full screen.
    final t = ((_extent - _kRest) / (1.0 - _kRest)).clamp(0.0, 1.0);
    final bgOpacity = (1 - t).clamp(0.0, 1.0);
    final radius = lerpDouble(26, 0, t)!;
    final statusBar = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;
    final hasRail = widget.products.length > 1;
    // At rest the card floats clearly above the bottom edge; the circular dock
    // floats independently in the gap below it. Both shrink to 0 at full screen.
    final railReserve = hasRail ? _kRailHeight + _kRailGap + safeBottom : 24.0;
    final side = lerpDouble(16, 0, t)!;
    final bottomMargin = lerpDouble(railReserve, 0, t)!;

    return Stack(
      children: [
        Positioned.fill(
          child: Opacity(
            opacity: bgOpacity,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(color: Colors.black.withValues(alpha: 0.25)),
              ),
            ),
          ),
        ),
        NotificationListener<DraggableScrollableNotification>(
          onNotification: _onNotification,
          child: DraggableScrollableSheet(
            controller: _sheet,
            initialChildSize: _kRest,
            minChildSize: _kMin,
            maxChildSize: 1.0,
            snap: true,
            snapSizes: const [_kRest, 1.0],
            builder: (context, sheetScroll) {
              return Padding(
                padding: EdgeInsets.only(
                    left: side, right: side, bottom: bottomMargin),
                child: Material(
                  color: context.colors.surface,
                  elevation: 12,
                  shadowColor: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(radius),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      _Header(
                        topInset: statusBar * t,
                        productId: widget.products[_index].id,
                        onCollapse: _collapseOrClose,
                      ),
                      Expanded(
                        child: PageView.builder(
                          controller: _page,
                          physics: _isFull
                              ? const NeverScrollableScrollPhysics()
                              : const PageScrollPhysics(),
                          onPageChanged: _onContentChanged,
                          itemCount: widget.products.length,
                          itemBuilder: (_, i) => _ProductPage(
                            productId: widget.products[i].id,
                            scrollController: _controllerFor(i, sheetScroll),
                            active: i == _index,
                          ),
                        ),
                      ),
                      _SharedCta(product: widget.products[_index]),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // Layer 5 — independent floating circular dock. Lives in the gap BELOW
        // the floating card (not inside it); fades out as the card expands and
        // is gone in full-page mode.
        if (hasRail)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: _isFull || t > 0.5,
              child: Opacity(
                opacity: (1 - t).clamp(0.0, 1.0),
                child: _CircularRail(
                  products: widget.products,
                  controller: _dock,
                  height: _kRailHeight,
                  bottomInset: safeBottom,
                  onTap: _selectFromRail,
                  onPageChanged: _onDockChanged,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Top chrome: collapse arrow (left), wishlist + share (right). No count, no ✕.
class _Header extends ConsumerWidget {
  const _Header({
    required this.topInset,
    required this.productId,
    required this.onCollapse,
  });

  final double topInset;
  final String productId;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    final wishlisted = ref.watch(isWishlistedProvider(productId));
    return Padding(
      padding: EdgeInsets.fromLTRB(
          AppSpacing.md, topInset + AppSpacing.sm, AppSpacing.md, AppSpacing.xs),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: vs.border, borderRadius: BorderRadius.circular(2)),
          ),
          AppSpacing.vGapSm,
          Row(
            children: [
              _RoundIconButton(
                  icon: Icons.keyboard_arrow_down_rounded, onTap: onCollapse),
              const Spacer(),
              _RoundIconButton(
                icon: wishlisted
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: wishlisted ? vs.danger : null,
                onTap: () {
                  ref.read(wishlistProvider.notifier).toggle(productId);
                  context.showSnack(wishlisted
                      ? 'Removed from wishlist'
                      : 'Added to wishlist');
                },
              ),
              AppSpacing.hGapSm,
              _RoundIconButton(
                icon: Icons.share_outlined,
                onTap: () {
                  ref
                      .read(analyticsServiceProvider)
                      .track('product_shared', {'product': productId});
                  context.showSnack('Share link copied');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap, this.color});

  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Material(
      color: vs.brandTint.withValues(alpha: 0.6),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          height: 36,
          width: 36,
          child: Icon(icon, size: 20, color: color ?? context.colors.onSurface),
        ),
      ),
    );
  }
}

/// One product card. Uses the provided [scrollController] (the sheet's when it's
/// the active card) so scrolling up first expands the sheet, then scrolls.
class _ProductPage extends ConsumerStatefulWidget {
  const _ProductPage({
    required this.productId,
    required this.scrollController,
    required this.active,
  });

  final String productId;
  final ScrollController scrollController;

  /// Only the centered card heroes its image (so the open/close morph pairs with
  /// exactly one grid card — no duplicate hero tags).
  final bool active;

  @override
  ConsumerState<_ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends ConsumerState<_ProductPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final vs = context.vsColors;
    final id = widget.productId;
    final state = ref.watch(productDetailControllerProvider(id));
    final controller = ref.read(productDetailControllerProvider(id).notifier);

    if (state.product == null) {
      if (state.error != null) {
        return VSErrorView(failure: state.error, onRetry: controller.retry);
      }
      return const VSLoadingView();
    }

    final p = state.product!;
    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Shared hero: the active card's image morphs from / back into the
          // product card in the grid (productHeroTag). The flight shuttle flies
          // the cached image so the first open never fades.
          widget.active
              ? Hero(
                  tag: productHeroTag(id),
                  flightShuttleBuilder: (_, __, ___, ____, _____) =>
                      VSNetworkImage(
                    url: p.gallery.isNotEmpty ? p.gallery.first : p.imageUrl,
                    fit: BoxFit.cover,
                  ),
                  child: VSProductGallery(images: p.gallery),
                )
              : VSProductGallery(images: p.gallery),
          Padding(
            padding: AppSpacing.screen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('${p.brand.toUpperCase()} · ${p.unit}',
                          style: AppTypography.labelSmall
                              .copyWith(color: vs.brand, letterSpacing: 0.5)),
                    ),
                    VSStockStatus(
                        status: state.stockStatus, stockCount: p.stockCount),
                  ],
                ),
                AppSpacing.vGapXs,
                Text(p.name, style: AppTypography.headlineSmall),
                AppSpacing.vGapSm,
                Row(
                  children: [
                    const Icon(Icons.star_rounded,
                        color: AppColors.warning, size: 18),
                    const SizedBox(width: AppSpacing.xs),
                    Text('${p.rating}', style: AppTypography.labelMedium),
                    const SizedBox(width: AppSpacing.xs),
                    Text('(${p.reviews} reviews)',
                        style: AppTypography.bodySmall
                            .copyWith(color: vs.textSecondary)),
                  ],
                ),
                AppSpacing.vGapMd,
                VSPriceWidget(price: state.pricing, large: true),
                if (p.variants.isNotEmpty) ...[
                  AppSpacing.vGapLg,
                  Text('Select Variation', style: AppTypography.titleMedium),
                  AppSpacing.vGapSm,
                  VSVariantSelector(
                    variants: p.variants,
                    selectedIndex: state.variantIndex,
                    onSelect: controller.selectVariant,
                  ),
                ],
                AppSpacing.vGapLg,
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Quantity', style: AppTypography.titleMedium),
                    VSQuantitySelector(
                      quantity: state.quantity,
                      max: state.maxQuantity,
                      onChanged: controller.setQuantity,
                    ),
                  ],
                ),
                const Divider(height: AppSpacing.xxl),
                Text('Description', style: AppTypography.titleMedium),
                AppSpacing.vGapSm,
                Text(
                  p.description ??
                      'Farm-fresh and hand-selected for quality, delivered at '
                          'peak freshness.',
                  style: AppTypography.bodyMedium
                      .copyWith(color: vs.textSecondary, height: 1.6),
                ),
                AppSpacing.vGapLg,
                VSSpecificationSection(specifications: p.specifications),
                const Divider(height: AppSpacing.xxl),
                ProductReviewsSection(productId: p.id),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared add-to-cart bar reflecting the currently centered product.
class _SharedCta extends ConsumerWidget {
  const _SharedCta({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    final detail = ref.watch(productDetailControllerProvider(product.id));
    final qty = ref.watch(
        cartControllerProvider.select((c) => c.quantityOf(product.id)));
    final cart = ref.read(cartControllerProvider.notifier);
    final inCart = qty > 0;
    final total = detail.product == null ? product.price : detail.lineTotal;
    final enabled =
        detail.product == null ? product.inStock : detail.canPurchase;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: vs.border)),
      ),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Total',
                  style: AppTypography.bodySmall
                      .copyWith(color: vs.textSecondary)),
              Text(total.asCurrency, style: AppTypography.priceMedium),
            ],
          ),
          AppSpacing.hGapLg,
          Expanded(
            child: inCart
                ? Row(
                    children: [
                      _MiniStepper(
                        quantity: qty,
                        onAdd: () {
                          HapticFeedback.selectionClick();
                          cart.increment(product.id);
                        },
                        onRemove: () {
                          HapticFeedback.selectionClick();
                          cart.decrement(product.id);
                        },
                      ),
                      AppSpacing.hGapSm,
                      Expanded(
                        child: VSButton(
                          label: 'Go to Cart',
                          onPressed: () {
                            Navigator.of(context).maybePop();
                            context.goNamed(RouteNames.cart);
                          },
                        ),
                      ),
                    ],
                  )
                : VSButton(
                    label: enabled ? 'Add to Cart' : 'Out of Stock',
                    onPressed: enabled
                        ? () {
                            HapticFeedback.mediumImpact();
                            cart.addProduct(product,
                                quantity: detail.product == null
                                    ? 1
                                    : detail.quantity);
                            context.showSnack('${product.name} added to cart');
                          }
                        : null,
                  ),
          ),
        ],
      ),
    );
  }
}

class _MiniStepper extends StatelessWidget {
  const _MiniStepper({
    required this.quantity,
    required this.onAdd,
    required this.onRemove,
  });

  final int quantity;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: AppColors.vsGreen,
        borderRadius: AppRadius.brMd,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn(Icons.remove_rounded, onRemove),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Text('$quantity',
                style:
                    AppTypography.titleMedium.copyWith(color: AppColors.white)),
          ),
          _btn(Icons.add_rounded, onAdd),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 48,
          width: 40,
          child: Icon(icon, color: AppColors.white, size: 20),
        ),
      );
}

/// Visual-only circular product wheel. It re-centers on the active product
/// (animating smoothly) and lets you TAP a thumbnail to switch — it is not a
/// draggable carousel and never moves the sheet. Center = 1.3× + ring + glow;
/// neighbours shrink, fade and drop into an arc.
class _CircularRail extends StatelessWidget {
  const _CircularRail({
    required this.products,
    required this.controller,
    required this.height,
    required this.bottomInset,
    required this.onTap,
    required this.onPageChanged,
  });

  final List<Product> products;
  final PageController controller;
  final double height;
  final double bottomInset;
  final ValueChanged<int> onTap;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height + bottomInset,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        // A real, draggable pager: swipe to scroll through products, snaps to
        // the centered thumbnail (which is the active product), synced with the
        // card. Tap a thumbnail to jump to it.
        child: PageView.builder(
          controller: controller,
          onPageChanged: onPageChanged,
          itemCount: products.length,
          physics: const BouncingScrollPhysics(),
          padEnds: true,
          itemBuilder: (context, i) => AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              double page;
              try {
                page = controller.page ?? controller.initialPage.toDouble();
              } catch (_) {
                page = controller.initialPage.toDouble();
              }
              final ad = (i - page).abs();
              final scale = (1.3 - ad * 0.34).clamp(0.55, 1.3);
              final opacity = (1.0 - ad * 0.32).clamp(0.0, 1.0);
              final dy = ad * 10.0; // side items dip into a gentle arc
              return Center(
                child: Opacity(
                  opacity: opacity,
                  child: Transform.translate(
                    offset: Offset(0, dy),
                    child: Transform.scale(
                      scale: scale,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onTap(i),
                        child:
                            _RailThumb(product: products[i], active: ad < 0.5),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RailThumb extends StatelessWidget {
  const _RailThumb({required this.product, required this.active});

  final Product product;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      height: 54,
      width: 54,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: context.colors.surface,
        shape: BoxShape.circle,
        border: Border.all(
          color: active ? vs.brand : vs.border,
          width: active ? 2.5 : 1,
        ),
        boxShadow: active ? AppShadows.glow(AppColors.vsGreen) : AppShadows.xs,
      ),
      clipBehavior: Clip.antiAlias,
      child: VSNetworkImage(
        url: product.imageUrl,
        fit: BoxFit.contain,
        fallbackIcon: Icons.shopping_basket_rounded,
      ),
    );
  }
}
