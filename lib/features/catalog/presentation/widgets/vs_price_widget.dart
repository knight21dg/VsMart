import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/product_price.dart';

/// Renders a [ProductPrice]: selling price, struck-through MRP, a discount chip,
/// and (optionally) the VS Credit price line.
class VSPriceWidget extends StatelessWidget {
  const VSPriceWidget({
    super.key,
    required this.price,
    this.large = false,
    this.showCredit = false,
    this.showDiscountChip = true,
  });

  final ProductPrice price;
  final bool large;
  final bool showCredit;
  final bool showDiscountChip;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              price.sellingPrice.asCurrency,
              style: large ? AppTypography.priceLarge : AppTypography.priceMedium,
            ),
            if (price.hasDiscount) ...[
              AppSpacing.hGapSm,
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  price.mrp.asCurrency,
                  style: AppTypography.bodySmall.copyWith(
                    color: vs.textSecondary,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ),
            ],
            if (showDiscountChip && price.hasDiscount) ...[
              AppSpacing.hGapSm,
              VSStatusChip(
                label: '${price.discountPercent}% OFF',
                tone: VSStatusTone.offer,
                dense: true,
              ),
            ],
          ],
        ),
        if (showCredit) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.account_balance_wallet_rounded,
                  size: 14, color: vs.trust),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '${price.effectiveCreditPrice.asCurrency} on VS Credit',
                style: AppTypography.labelMedium.copyWith(color: vs.trust),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
