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
import '../../../wishlist/presentation/providers/wishlist_providers.dart';
import '../../domain/entities/product.dart';
import '../product_navigation.dart';
import '../providers/product_detail_controller.dart';
import '../widgets/product_detail_widgets.dart';
import '../widgets/vs_price_widget.dart';
import '../widgets/product_suggestions_rail.dart';
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
  // Safe only after the null-id guard in build() — this screen renders an error
  // state when no product id was routed in.
  String get _id => widget.productId!;

  @override
  Widget build(BuildContext context) {
    // No product id was routed in (e.g. a malformed deep link). Show an honest
    // error state instead of fetching a demo product.
    if (widget.productId == null) {
      return Scaffold(
        appBar: AppBar(title: Text(context.l10n.catalogProductDetails)),
        body: VSErrorView(message: context.l10n.catalogProductNotFound),
      );
    }
    final vs = context.vsColors;
    final wishlisted = ref.watch(isWishlistedProvider(_id));
    final state = ref.watch(productDetailControllerProvider(_id));
    final controller =
        ref.read(productDetailControllerProvider(_id).notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.catalogProductDetails),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: context.l10n.commonShare,
            // Only shareable once the product has loaded (we share its name/price).
            onPressed: state.product == null
                ? null
                : () => _shareProduct(state.product!),
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
                wishlisted
                    ? context.l10n.catalogRemovedFromWishlist
                    : context.l10n.catalogAddedToWishlist,
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
              // Mirrors CartItem.lineKey so the stepper drives the line the
              // Add button actually created.
              lineKey: state.selectedVariant == null
                  ? state.product!.id
                  : '${state.product!.id}:${state.selectedVariant!.id}',
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

  /// Hand the product's canonical link to the OS share sheet (WhatsApp, etc.).
  Future<void> _shareProduct(Product product) async {
    try {
      await ref.read(shareServiceProvider).shareProduct(
            productId: product.id,
            shareToken: product.shareToken,
            name: product.name,
            brand: product.brand,
            price: product.price,
          );
      ref
          .read(analyticsServiceProvider)
          .track('product_shared', {'product': product.id});
    } catch (_) {
      if (!mounted) return;
      context.showSnack(context.l10n.catalogShareSheetError, isError: true);
    }
  }

  void _addToCart(DetailState state, {required String event}) {
    final product = state.product;
    if (product == null) return;
    ref
        .read(cartControllerProvider.notifier)
        // Pass the SELECTED variant: its priceDelta is what the screen has been
        // showing, so it's what the cart must charge.
        .addProduct(product, quantity: state.quantity, variant: state.selectedVariant);
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

    // Feed the gallery the card's thumbnail as the first-image warm placeholder,
    // so the hero shows the (already-cached) picture on the very first open and
    // cross-fades to the full gallery image — no shimmer/loading on the image.
    // When the chosen pack has its OWN photo, lead with it so selecting a variant
    // swaps the picture (the base gallery stays available behind it).
    final variantImage = state.selectedVariant?.imageUrl;
    final galleryImages = (variantImage != null && variantImage.isNotEmpty)
        ? [variantImage, ...p.gallery.where((g) => g != variantImage)]
        : p.gallery;
    final gallery = VSProductGallery(
      images: galleryImages,
      heroFallbackUrl: variantImage?.isNotEmpty == true ? variantImage : p.imageUrl,
    );
    // Land the incoming flight on the gallery. When a card threaded its exact
    // tag we use it; otherwise default to `product_image_<id>` so the Hero is
    // still well-formed (an unmatched tag simply renders with no flight).
    final tag = heroTag ?? 'product_image_${p.id}';
    return RefreshIndicator(
      onRefresh: controller.retry,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
        Hero(
          tag: tag,
          // Fly the SAME image the source card showed (its thumbnail, already
          // cached) so the flight itself never shimmers.
          flightShuttleBuilder: (_, __, ___, ____, _____) => VSNetworkImage(
            url: p.imageUrl ?? (p.gallery.isNotEmpty ? p.gallery.first : null),
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
              // NOTE: no rating/reviews on products — for groceries they add no
              // value. Feedback is collected per-ORDER instead (orders feature).
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
                Text(context.l10n.catalogSelectVariation,
                    style: AppTypography.titleMedium),
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
                  Text(context.l10n.catalogQuantity,
                      style: AppTypography.titleMedium),
                  VSQuantitySelector(
                    quantity: state.quantity,
                    max: state.maxQuantity,
                    onChanged: controller.setQuantity,
                  ),
                ],
              ),
              const Divider(height: AppSpacing.xxl),
              Text(context.l10n.catalogDescription,
                  style: AppTypography.titleMedium),
              AppSpacing.vGapSm,
              Text(
                p.description ?? context.l10n.catalogDefaultDescription,
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
              // Product reviews intentionally removed — feedback lives on the
              // order (post-delivery), not on grocery products.
            ],
          ),
        ),
        const Divider(height: AppSpacing.xxl),
        // Same shared rail the product overlay uses, so every product surface
        // suggests identically.
        ProductSuggestionsRail(
          excludeId: p.id,
          title: context.l10n.catalogYouMayAlsoLike,
          onTapProduct: (other) => context.pushReplacementNamed(
            RouteNames.productDetails,
            pathParameters: {'productId': other.id},
            extra: detailHeroTag('suggestions', other.id),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
      ),
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
                Text(context.l10n.catalogEligibleForCredit,
                    style: AppTypography.titleMedium
                        .copyWith(color: AppColors.white)),
                Text(context.l10n.catalogBuyNowPayLater,
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

class _StickyCta extends ConsumerWidget {
  const _StickyCta({
    required this.lineKey,
    required this.total,
    required this.enabled,
    required this.onAddToCart,
    required this.onBuyNow,
  });

  /// The cart LINE this bar controls — `productId` for a variant-less product,
  /// `productId:variantId` once a variant is selected. Stepping the bare
  /// productId would adjust the wrong line (or none) for a variant.
  final String lineKey;
  final num total;
  final bool enabled;
  final VoidCallback onAddToCart;
  final VoidCallback onBuyNow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    final inCart = ref.watch(
        cartControllerProvider.select((c) => c.quantityOf(lineKey) > 0));

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
                Text(context.l10n.cartTotal,
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
                // Once the item is in the cart the bar is a single Go-to-Cart
                // action. It used to also carry a stepper, which duplicated the
                // Quantity selector in the page body — two controls for the same
                // idea, disagreeing with each other (one set the amount to add,
                // the other edited the cart line).
                child: inCart
                    ? VSButton(
                        key: const ValueKey('in-cart'),
                        label: context.l10n.catalogGoToCart,
                        onPressed: () => context.goNamed(RouteNames.cart),
                      )
                    : Row(
                        key: const ValueKey('not-in-cart'),
                        children: [
                          Expanded(
                            child: VSOutlinedButton(
                              label: context.l10n.productAddToCart,
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
                              label: enabled
                                  ? context.l10n.commonBuyNow
                                  : context.l10n.productOutOfStock,
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

