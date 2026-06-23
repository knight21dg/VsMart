import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/product_variant.dart';

/// Selectable variant chips. A variant changes the SKU, pricing and stock.
class VSVariantSelector extends StatelessWidget {
  const VSVariantSelector({
    super.key,
    required this.variants,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<ProductVariant> variants;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (var i = 0; i < variants.length; i++)
          _VariantChip(
            label: variants[i].label,
            selected: i == selectedIndex,
            enabled: variants[i].inStock,
            onTap: variants[i].inStock ? () => onSelect(i) : null,
            disabledColor: vs.textSecondary,
          ),
      ],
    );
  }
}

class _VariantChip extends StatelessWidget {
  const _VariantChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.disabledColor,
    this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final Color disabledColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brMd,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? vs.brandTint : context.colors.surface,
          borderRadius: AppRadius.brMd,
          border: Border.all(color: selected ? vs.brand : vs.border),
        ),
        child: Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: !enabled
                ? disabledColor
                : (selected ? vs.brand : null),
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            decoration: enabled ? null : TextDecoration.lineThrough,
          ),
        ),
      ),
    );
  }
}

/// Stepper bounded by [max] (the available stock), minimum 1.
class VSQuantitySelector extends StatelessWidget {
  const VSQuantitySelector({
    super.key,
    required this.quantity,
    required this.max,
    required this.onChanged,
  });

  final int quantity;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.brMd,
        border: Border.all(color: vs.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_rounded, size: 18),
            onPressed: quantity > 1 ? () => onChanged(quantity - 1) : null,
          ),
          Text('$quantity', style: AppTypography.titleMedium),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.add_rounded, size: 18, color: vs.brand),
            onPressed: quantity < max ? () => onChanged(quantity + 1) : null,
          ),
        ],
      ),
    );
  }
}

/// Availability badge with an urgency message for low stock.
class VSStockStatus extends StatelessWidget {
  const VSStockStatus({super.key, required this.status, this.stockCount});

  final StockStatus status;
  final int? stockCount;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      StockStatus.inStock => const VSStatusChip(
          label: 'In Stock',
          tone: VSStatusTone.success,
          icon: Icons.check_circle_rounded,
        ),
      StockStatus.lowStock => VSStatusChip(
          label: stockCount != null ? 'Only $stockCount left!' : 'Low stock',
          tone: VSStatusTone.warning,
          icon: Icons.bolt_rounded,
        ),
      StockStatus.outOfStock => const VSStatusChip(
          label: 'Out of Stock',
          tone: VSStatusTone.danger,
          icon: Icons.remove_shopping_cart_rounded,
        ),
    };
  }
}

/// Reusable key/value specifications table.
class VSSpecificationSection extends StatelessWidget {
  const VSSpecificationSection({super.key, required this.specifications});

  final Map<String, String> specifications;

  @override
  Widget build(BuildContext context) {
    if (specifications.isEmpty) return const SizedBox.shrink();
    final vs = context.vsColors;
    final entries = specifications.entries.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Specifications', style: AppTypography.titleMedium),
        AppSpacing.vGapSm,
        Container(
          decoration: BoxDecoration(
            borderRadius: AppRadius.brLg,
            border: Border.all(color: vs.border),
          ),
          child: Column(
            children: [
              for (var i = 0; i < entries.length; i++)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.md),
                  decoration: BoxDecoration(
                    border: i == entries.length - 1
                        ? null
                        : Border(bottom: BorderSide(color: vs.border)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 130,
                        child: Text(entries[i].key,
                            style: AppTypography.bodyMedium
                                .copyWith(color: vs.textSecondary)),
                      ),
                      Expanded(
                        child: Text(entries[i].value,
                            style: AppTypography.bodyMedium),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
