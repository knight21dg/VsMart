import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../cart/presentation/providers/cart_providers.dart';
import '../../../catalog/domain/entities/product.dart';
import '../../../catalog/presentation/providers/catalog_providers.dart';
import '../../../offers/presentation/providers/offer_providers.dart';
import '../../../orders/presentation/providers/order_providers.dart';
import '../../../wishlist/presentation/providers/wishlist_providers.dart';
import '../product_navigation.dart';

enum ProductSection { popular, recommended, recentlyOrdered, sales }

class ProductSectionScreen extends ConsumerWidget {
  const ProductSectionScreen({
    super.key,
    required this.section,
  });

  final ProductSection section;

  String get _title => switch (section) {
        ProductSection.popular => 'Popular Products',
        ProductSection.recommended => 'Recommended for You',
        ProductSection.recentlyOrdered => 'Recently Ordered',
        ProductSection.sales => 'Sales Products',
      };

  String get _emptyMessage => switch (section) {
        ProductSection.popular => 'No popular products available.',
        ProductSection.recommended => 'No recommendations yet.',
        ProductSection.recentlyOrdered => 'No recent orders.',
        ProductSection.sales => 'No sale products available.',
      };

  IconData get _emptyIcon => switch (section) {
        ProductSection.popular => Icons.trending_up_rounded,
        ProductSection.recommended => Icons.thumb_up_outlined,
        ProductSection.recentlyOrdered => Icons.history_rounded,
        ProductSection.sales => Icons.local_offer_outlined,
      };

  String get _subtitle => switch (section) {
        ProductSection.popular => 'Top-selling picks loved by VS Mart shoppers',
        ProductSection.recommended => 'Handpicked for you based on your shopping',
        ProductSection.recentlyOrdered => 'Quickly reorder what you bought before',
        ProductSection.sales => 'Best discounts and deals available right now',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = _getProvider(ref);

    return Scaffold(
      appBar: VSAppBar(title: _title),
      body: async.when(
        loading: () => const VSLoadingView(),
        error: (_, __) => const VSErrorView(),
        data: (products) {
          if (products.isEmpty) {
            return VSEmptyState(
              icon: _emptyIcon,
              title: 'Nothing here',
              message: _emptyMessage,
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionIntro(
                icon: _emptyIcon,
                subtitle: _subtitle,
                count: products.length,
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: AppSpacing.md,
                    crossAxisSpacing: AppSpacing.md,
                    childAspectRatio: 0.62,
                  ),
                  itemCount: products.length,
                  itemBuilder: (context, i) =>
                      _ProductGridItem(product: products[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  AsyncValue<List<Product>> _getProvider(WidgetRef ref) {
    switch (section) {
      case ProductSection.popular:
        return ref.watch(popularProductsProvider);
      case ProductSection.recommended:
        return ref.watch(recommendedProductsProvider);
      case ProductSection.recentlyOrdered:
        return ref.watch(recentlyOrderedProductsProvider);
      case ProductSection.sales:
        return ref.watch(dealsProductsProvider);
    }
  }
}

/// Compact section banner shown above the grid so each section page reads as a
/// distinct, purpose-built screen.
class _SectionIntro extends StatelessWidget {
  const _SectionIntro({
    required this.icon,
    required this.subtitle,
    required this.count,
  });

  final IconData icon;
  final String subtitle;
  final int count;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      margin: AppSpacing.screen,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [vs.brandTint, vs.brandTint.withValues(alpha: 0.3)],
        ),
        borderRadius: AppRadius.brLg,
      ),
      child: Row(
        children: [
          Container(
            height: 48,
            width: 48,
            decoration:
                BoxDecoration(color: context.colors.surface, shape: BoxShape.circle),
            child: Icon(icon, color: vs.brand, size: 26),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$count item${count == 1 ? '' : 's'}',
                    style:
                        AppTypography.labelMedium.copyWith(color: vs.brand)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: AppTypography.bodySmall
                        .copyWith(color: vs.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductGridItem extends ConsumerWidget {
  const _ProductGridItem({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final qty = ref.watch(cartControllerProvider).quantityOf(product.id);
    final wishlisted = ref.watch(isWishlistedProvider(product.id));
    return VSProductCard(
      name: product.name,
      unitLabel: product.unit,
      price: product.price,
      mrp: product.mrp,
      rating: product.rating,
      reviews: product.reviews,
      imageUrl: product.imageUrl,
      outOfStock: !product.inStock,
      inWishlist: wishlisted,
      quantityInCart: qty,
      heroTag: detailHeroTag('section', product.id),
      onWishlistTap: () => ref.read(wishlistProvider.notifier).toggle(product.id),
      onTap: () =>
          openProductDetail(context, productId: product.id, source: 'section'),
      onAdd: () => ref.read(cartControllerProvider.notifier).addProduct(product),
      onIncrement: () =>
          ref.read(cartControllerProvider.notifier).increment(product.id),
      onDecrement: () =>
          ref.read(cartControllerProvider.notifier).decrement(product.id),
    );
  }
}

final dealsProductsProvider = FutureProvider<List<Product>>((ref) async {
  final deals = await ref.watch(dealsProvider.future);
  final products = <Product>[];
  for (final deal in deals) {
    if (deal.productId != null) {
      try {
        final product = await ref.watch(productByIdProvider(deal.productId!).future);
        products.add(product);
      } catch (_) {}
    }
  }
  return products;
});
