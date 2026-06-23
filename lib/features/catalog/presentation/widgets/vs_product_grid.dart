import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/product.dart';
import 'product_overlay.dart';

/// Reusable product grid as a sliver, for use inside a `CustomScrollView`
/// (Listing, Search, Wishlist, Offers).
class VSProductGrid extends StatelessWidget {
  const VSProductGrid({
    super.key,
    required this.products,
    required this.onTap,
    required this.onAdd,
    this.quantityOf,
    this.onIncrement,
    this.onDecrement,
    this.isWishlisted,
    this.onWishlistToggle,
    this.heroTags = false,
  });

  final List<Product> products;
  final ValueChanged<Product> onTap;
  final ValueChanged<Product> onAdd;
  final int Function(Product)? quantityOf;
  final ValueChanged<Product>? onIncrement;
  final ValueChanged<Product>? onDecrement;
  final bool Function(Product)? isWishlisted;
  final ValueChanged<Product>? onWishlistToggle;

  /// Give each card's image a Hero tag so it morphs into the product overlay.
  final bool heroTags;

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
        childAspectRatio: 0.62,
      ),
      delegate: SliverChildBuilderDelegate(
        (_, i) {
          final p = products[i];
          final qty = quantityOf?.call(p) ?? 0;
          return VSProductCard(
            name: p.name,
            unitLabel: p.unit,
            price: p.price,
            mrp: p.mrp,
            rating: p.rating,
            reviews: p.reviews,
            imageUrl: p.imageUrl,
            outOfStock: !p.inStock,
            quantityInCart: qty,
            inWishlist: isWishlisted?.call(p) ?? false,
            heroTag: heroTags ? productHeroTag(p.id) : null,
            onTap: () => onTap(p),
            onAdd: () => onAdd(p),
            onIncrement: onIncrement == null ? null : () => onIncrement!(p),
            onDecrement: onDecrement == null ? null : () => onDecrement!(p),
            onWishlistTap: onWishlistToggle == null
                ? null
                : () => onWishlistToggle!(p),
          );
        },
        childCount: products.length,
      ),
    );
  }
}
