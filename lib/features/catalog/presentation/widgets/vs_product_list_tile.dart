import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/product.dart';
import 'vs_price_widget.dart';

/// Single-row product tile for the list view of a listing.
class VSProductListTile extends StatelessWidget {
  const VSProductListTile({
    super.key,
    required this.product,
    required this.onTap,
    required this.onAdd,
    this.quantity = 0,
    this.heroTag,
  });

  final Product product;
  final VoidCallback onTap;
  final VoidCallback onAdd;
  final int quantity;

  /// When set, the thumbnail is a [Hero] with this tag so it morphs into the
  /// product overlay/detail surface on open (and back on close).
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final p = product;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brLg,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: AppRadius.brLg,
          border: Border.all(color: vs.border),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: AppRadius.brMd,
              child: SizedBox(
                height: 64,
                width: 64,
                child: heroTag == null
                    ? VSNetworkImage(url: p.imageUrl, fit: BoxFit.cover)
                    : Hero(
                        tag: heroTag!,
                        flightShuttleBuilder: (_, __, ___, ____, _____) =>
                            VSNetworkImage(url: p.imageUrl, fit: BoxFit.cover),
                        child: VSNetworkImage(url: p.imageUrl, fit: BoxFit.cover),
                      ),
              ),
            ),
            AppSpacing.hGapMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.titleMedium),
                  Text('${p.brand} · ${p.unit}',
                      style: AppTypography.bodySmall
                          .copyWith(color: vs.textSecondary)),
                  AppSpacing.vGapXs,
                  VSPriceWidget(price: p.pricing),
                ],
              ),
            ),
            AppSpacing.hGapSm,
            if (!p.inStock)
              Text('Out of stock',
                  style: AppTypography.labelSmall.copyWith(color: vs.danger))
            else
              _AddControl(quantity: quantity, onAdd: onAdd),
          ],
        ),
      ),
    );
  }
}

/// Compact add-to-cart control for the list tile: an icon-only "+" button that
/// turns into a brand-filled quantity chip once the item is in the cart. No
/// "ADD" text label by design.
class _AddControl extends StatelessWidget {
  const _AddControl({required this.quantity, required this.onAdd});

  final int quantity;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    if (quantity > 0) {
      return GestureDetector(
        onTap: onAdd,
        child: Container(
          height: 36,
          constraints: const BoxConstraints(minWidth: 36),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: vs.brand,
            borderRadius: AppRadius.brSm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$quantity',
                  style: AppTypography.labelMedium
                      .copyWith(color: AppColors.white)),
              const SizedBox(width: 2),
              const Icon(Icons.add_rounded, size: 16, color: AppColors.white),
            ],
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: onAdd,
      child: Container(
        height: 36,
        width: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: vs.brandTint,
          borderRadius: AppRadius.brSm,
          border: Border.all(color: vs.brand),
        ),
        child: Icon(Icons.add_rounded, size: 20, color: vs.brand),
      ),
    );
  }
}
