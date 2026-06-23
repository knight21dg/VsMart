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
import '../../../credit/domain/credit_access.dart';
import '../../../credit/presentation/providers/credit_access_provider.dart';
import '../../../offers/presentation/widgets/placement_banner_carousel.dart';
import '../../../reviews/presentation/widgets/product_reviews_section.dart';
import '../../../wishlist/presentation/providers/wishlist_providers.dart';
import '../../domain/entities/product.dart';
import '../product_navigation.dart';
import '../providers/catalog_providers.dart';
import '../providers/product_detail_controller.dart';
import '../widgets/product_detail_widgets.dart';
import '../widgets/vs_price_widget.dart';
import '../widgets/vs_product_gallery.dart';

/// Pure view over [productDetailControllerProvider]. All product-interaction
/// logic (variant, quantity, stock, recently-viewed) lives in the controller.
class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({super.key, this.productId, this.heroTag});

  final String? productId;

  /// Shared-element tag so the opening card's image morphs into this gallery.
  final String? heroTag;

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  String get _id => widget.productId ?? 'avocado';

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final wishlisted = ref.watch(isWishlistedProvider(_id));
    final state = ref.watch(productDetailControllerProvider(_id));
    final controller =
        ref.read(productDetailControllerProvider(_id).notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: () {
              ref
                  .read(analyticsServiceProvider)
                  .track('product_shared', {'product': _id});
              context.showSnack('Share link copied');
            },
          ),
          IconButton(
            icon: Icon(
              wishlisted
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: wishlisted ? vs.danger : null,
            ),
            onPressed: () {
              ref.read(wishlistProvider.notifier).toggle(_id);
              context.showSnack(
                wishlisted ? 'Removed from wishlist' : 'Added to wishlist',
              );
            },
          ),
        ],
      ),
      body: state.loading
          ? const VSLoadingView()
          : state.error != null
              ? VSErrorView(failure: state.error, onRetry: controller.retry)
              : _Body(
                  state: state,
                  controller: controller,
                  heroTag: widget.heroTag,
                ),
      bottomNavigationBar: state.product == null
          ? null
          : _StickyCta(
              productId: state.product!.id,
              total: state.lineTotal,
              enabled: state.canPurchase,
              onAddToCart: () => _addToCart(state, event: 'add_to_cart'),
              onBuyNow: () {
                _addToCart(state, event: 'buy_now');
                context.pushNamed(RouteNames.checkout);
              },
            ),
    );
  }

  void _addToCart(DetailState state, {required String event}) {
    final product = state.product;
    if (product == null) return;
    ref
        .read(cartControllerProvider.notifier)
        .addProduct(product, quantity: state.quantity);
    ref.read(analyticsServiceProvider).track(event, {
      'product': product.id,
      'quantity': state.quantity,
    });
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.state,
    required this.controller,
    this.heroTag,
  });

  final DetailState state;
  final ProductDetailController controller;
  final String? heroTag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    final p = state.product!;
    final pricing = state.pricing;
    final fbt = ref.watch(recommendedProductsProvider).maybeWhen(
          data: (list) => list.where((x) => x.id != p.id).take(6).toList(),
          orElse: () => const <Product>[],
        );

    final gallery = VSProductGallery(images: p.gallery);
    // Land the incoming flight on the gallery. When a card threaded its exact
    // tag we use it; otherwise default to `product_image_<id>` so the Hero is
    // still well-formed (an unmatched tag simply renders with no flight).
    final tag = heroTag ?? 'product_image_${p.id}';
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Hero(
          tag: tag,
          flightShuttleBuilder: (_, __, ___, ____, _____) => VSNetworkImage(
            url: p.gallery.isNotEmpty ? p.gallery.first : p.imageUrl,
            fit: BoxFit.cover,
          ),
          child: gallery,
        ),
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
                  VSStockStatus(status: state.stockStatus, stockCount: p.stockCount),
                ],
              ),
              AppSpacing.vGapXs,
              Text(p.name, style: AppTypography.headlineMedium),
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
              VSPriceWidget(
                price: pricing,
                large: true,
                showCredit: ref.watch(creditAccessProvider).isActive,
              ),
              // Only surface the VS Credit eligibility card to customers who
              // actually have an active credit line — no leak to non-applicants.
              if (ref.watch(creditAccessProvider).isActive) ...[
                AppSpacing.vGapLg,
                const _CreditEligibilityCard(),
              ],
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
              // Dynamic, category-targeted promo banner (renders nothing when
              // the server returns no banner for this product).
              PlacementBannerCarousel(
                placement: 'product_detail',
                categoryId: p.categoryId,
                single: true,
                padding: EdgeInsets.zero,
                trailingGap: AppSpacing.md,
              ),
              AppSpacing.vGapLg,
              VSSpecificationSection(specifications: p.specifications),
              AppSpacing.vGapLg,
              const Divider(height: AppSpacing.xxl),
              ProductReviewsSection(productId: p.id),
              if (fbt.isNotEmpty) ...[
                AppSpacing.vGapLg,
                Text('You May Also Like', style: AppTypography.titleLarge),
                AppSpacing.vGapMd,
              ],
            ],
          ),
        ),
        if (fbt.isNotEmpty) _RecommendedRail(products: fbt),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

class _CreditEligibilityCard extends StatelessWidget {
  const _CreditEligibilityCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: const BoxDecoration(
        gradient: AppColors.greenGradient,
        borderRadius: AppRadius.brLg,
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded, color: AppColors.white, size: 20),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Eligible for VS Credit',
                    style: AppTypography.titleMedium
                        .copyWith(color: AppColors.white)),
                Text('Buy now, pay later with zero interest.',
                    style: AppTypography.bodySmall.copyWith(
                        color: AppColors.white.withValues(alpha: 0.85))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendedRail extends StatelessWidget {
  const _RecommendedRail({required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 256,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: AppSpacing.screenHorizontal,
        itemCount: products.length,
        separatorBuilder: (_, __) => AppSpacing.hGapMd,
        itemBuilder: (context, i) {
          final p = products[i];
          final tag = detailHeroTag('related', p.id);
          return SizedBox(
            width: 160,
            child: VSProductCard(
              name: p.name,
              unitLabel: p.unit,
              price: p.price,
              mrp: p.mrp,
              rating: p.rating,
              imageUrl: p.imageUrl,
              outOfStock: !p.inStock,
              heroTag: tag,
              onTap: () => context.pushReplacementNamed(
                RouteNames.productDetails,
                pathParameters: {'productId': p.id},
                extra: tag,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Sticky bottom CTA. Before adding: Add to Cart + Buy Now. Once in the cart,
/// the Buy Now is dropped and the Add button morphs into a quantity stepper
/// (animated "expand pill") — with haptics on every change.
class _StickyCta extends ConsumerWidget {
  const _StickyCta({
    required this.productId,
    required this.total,
    required this.enabled,
    required this.onAddToCart,
    required this.onBuyNow,
  });

  final String productId;
  final num total;
  final bool enabled;
  final VoidCallback onAddToCart;
  final VoidCallback onBuyNow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    final qty = ref.watch(
        cartControllerProvider.select((c) => c.quantityOf(productId)));
    final cart = ref.read(cartControllerProvider.notifier);
    final inCart = qty > 0;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: vs.border)),
        boxShadow: AppShadows.sm,
      ),
      child: SafeArea(
        minimum: AppSpacing.screen,
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
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutBack,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.9, end: 1).animate(anim),
                    child: child,
                  ),
                ),
                child: inCart
                    ? Row(
                        key: const ValueKey('in-cart'),
                        children: [
                          Expanded(
                            child: _DetailStepper(
                              quantity: qty,
                              onAdd: () {
                                HapticFeedback.selectionClick();
                                cart.increment(productId);
                              },
                              onRemove: () {
                                HapticFeedback.selectionClick();
                                cart.decrement(productId);
                              },
                            ),
                          ),
                          AppSpacing.hGapSm,
                          Expanded(
                            child: VSButton(
                              label: 'Go to Cart',
                              onPressed: () => context.goNamed(RouteNames.cart),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        key: const ValueKey('not-in-cart'),
                        children: [
                          Expanded(
                            child: VSOutlinedButton(
                              label: 'Add to Cart',
                              onPressed: enabled
                                  ? () {
                                      HapticFeedback.mediumImpact();
                                      onAddToCart();
                                    }
                                  : null,
                            ),
                          ),
                          AppSpacing.hGapSm,
                          Expanded(
                            child: VSButton(
                              label: enabled ? 'Buy Now' : 'Out of Stock',
                              onPressed: enabled ? onBuyNow : null,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-width green quantity stepper used by the product-detail sticky bar.
class _DetailStepper extends StatelessWidget {
  const _DetailStepper({
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
      height: 52,
      decoration: const BoxDecoration(
        color: AppColors.vsGreen,
        borderRadius: AppRadius.brMd,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _StepBtn(icon: Icons.remove_rounded, onTap: onRemove),
          Text('$quantity',
              style:
                  AppTypography.titleLarge.copyWith(color: AppColors.white)),
          _StepBtn(icon: Icons.add_rounded, onTap: onAdd),
        ],
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 28,
      child: SizedBox(
        height: 52,
        width: 52,
        child: Icon(icon, color: AppColors.white),
      ),
    );
  }
}
