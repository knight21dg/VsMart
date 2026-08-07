import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../cart/presentation/providers/cart_providers.dart';
import '../../../wishlist/presentation/providers/wishlist_providers.dart';
import '../../domain/entities/product.dart';
import '../product_navigation.dart';
import '../product_share.dart';
import '../providers/catalog_providers.dart';

/// "You might also like" — one suggestions rail shared by EVERY product surface
/// (full detail page, the floating product overlay, and any future one).
///
/// Self-contained: it sources its own suggestions, and each card is a full
/// product card — add-to-cart, wishlist and share all work straight from the
/// rail, so a suggestion behaves exactly like a product anywhere else. The host
/// only supplies navigation, since a page pushes while the overlay swaps.
class ProductSuggestionsRail extends ConsumerWidget {
  const ProductSuggestionsRail({
    super.key,
    required this.excludeId,
    required this.onTapProduct,
    this.title,
    this.max = 10,
  });

  /// The product currently being viewed — never suggest the thing you're on.
  final String excludeId;
  final void Function(Product product) onTapProduct;
  final String? title;
  final int max;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(recommendedProductsProvider).maybeWhen(
          data: (list) =>
              list.where((p) => p.id != excludeId).take(max).toList(),
          orElse: () => const <Product>[],
        );
    if (products.isEmpty) return const SizedBox.shrink();
    final cart = ref.watch(cartControllerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: AppSpacing.screenHorizontal,
          child: Text(title ?? 'You might also like',
              style: AppTypography.titleMedium),
        ),
        AppSpacing.vGapMd,
        SizedBox(
          height: 236,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: AppSpacing.screenHorizontal,
            itemCount: products.length,
            separatorBuilder: (_, __) => AppSpacing.hGapMd,
            itemBuilder: (context, i) {
              final p = products[i];
              return SizedBox(
                width: 160,
                child: VSProductCard(
                  name: p.name,
                  unitLabel: p.unit,
                  price: p.displayPrice,
                  mrp: p.displayMrp,
                  imageUrl: p.imageUrl,
                  outOfStock: !p.effectiveInStock,
                  inWishlist: ref.watch(isWishlistedProvider(p.id)),
                  quantityInCart: cart.quantityOf(p.id),
                  onTap: () => onTapProduct(p),
                  onAdd: () {
                    addToCartOrChoose(context, ref, p, source: 'suggestions');
                    ref.read(analyticsServiceProvider).track(
                        'add_to_cart', {'product': p.id, 'source': 'suggestions'});
                  },
                  onIncrement: () =>
                      ref.read(cartControllerProvider.notifier).increment(p.id),
                  onDecrement: () =>
                      ref.read(cartControllerProvider.notifier).decrement(p.id),
                  onWishlistTap: () =>
                      ref.read(wishlistProvider.notifier).toggle(p.id),
                  onShareTap: () => shareProductLink(context, ref, p),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
