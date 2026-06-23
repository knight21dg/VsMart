import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/cart_item.dart';
import '../providers/cart_providers.dart';

/// A single editable cart line: thumbnail, name/unit, price, quantity stepper
/// (delete when reduced past 1), and an optional validation warning.
class VSCartItem extends StatelessWidget {
  const VSCartItem({
    super.key,
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    this.onTap,
    this.warning,
  });

  final CartItem item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  /// Tapping the line (outside the stepper) opens the product details page.
  final VoidCallback? onTap;
  final String? warning;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Material(
      color: context.colors.surface,
      borderRadius: AppRadius.brLg,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.brLg,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: AppRadius.brLg,
            border: Border.all(color: warning != null ? vs.warning : vs.border),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: AppRadius.brMd,
                    child: SizedBox(
                      height: 56,
                      width: 56,
                      child: item.imageUrl != null
                          ? VSNetworkImage(url: item.imageUrl, fit: BoxFit.cover)
                          : Container(
                              color: vs.brandTint,
                              child: Icon(Icons.shopping_basket_rounded,
                                  color: vs.brand),
                            ),
                    ),
                  ),
                  AppSpacing.hGapMd,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.titleMedium),
                        Text(item.unit,
                            style: AppTypography.bodySmall
                                .copyWith(color: vs.textSecondary)),
                        AppSpacing.vGapXs,
                        Row(
                          children: [
                            Text(item.price.asCurrency,
                                style: AppTypography.priceMedium),
                            if (item.mrp > item.price) ...[
                              AppSpacing.hGapSm,
                              Text(item.mrp.asCurrency,
                                  style: AppTypography.bodySmall.copyWith(
                                    color: vs.textSecondary,
                                    decoration: TextDecoration.lineThrough,
                                  )),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  _Stepper(
                    quantity: item.quantity,
                    onIncrement: onIncrement,
                    onDecrement: onDecrement,
                  ),
                ],
              ),
              if (warning != null) ...[
            AppSpacing.vGapSm,
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 14, color: vs.warning),
                AppSpacing.hGapSm,
                Expanded(
                  child: Text(warning!,
                      style: AppTypography.labelSmall
                          .copyWith(color: vs.warning)),
                ),
              ],
            ),
          ],
            ],
              ),
            ),
          ),
        );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.quantity,
    required this.onIncrement,
    required this.onDecrement,
  });

  final int quantity;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    Widget btn(IconData icon, VoidCallback onTap) => InkWell(
          onTap: onTap,
          child: SizedBox(
              height: 36,
              width: 36,
              child: Icon(icon, size: 18, color: vs.brand)),
        );
    return Container(
      decoration:
          BoxDecoration(color: vs.brandTint, borderRadius: AppRadius.brMd),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(
              quantity > 1
                  ? Icons.remove_rounded
                  : Icons.delete_outline_rounded,
              onDecrement),
          Text('$quantity',
              style: AppTypography.titleMedium.copyWith(color: vs.brand)),
          btn(Icons.add_rounded, onIncrement),
        ],
      ),
    );
  }
}

/// Bill breakdown card driven by [CartSummary].
class VSCartSummaryCard extends StatelessWidget {
  const VSCartSummaryCard({super.key, required this.summary});

  final CartSummary summary;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
      ),
      child: Column(
        children: [
          _row(context, 'Item Total', summary.subtotal.asCurrency),
          if (summary.savings > 0) ...[
            AppSpacing.vGapSm,
            _row(context, 'You Save', '- ${summary.savings.asCurrency}',
                color: vs.success),
          ],
          AppSpacing.vGapSm,
          summary.deliveryCharges == 0
              ? _row(context, 'Delivery Fee', 'FREE',
                  color: vs.success, strike: '₹$_deliveryFeeLabel')
              : _row(context, 'Delivery Fee', summary.deliveryCharges.asCurrency),
          if (summary.gstAmount > 0) ...[
            AppSpacing.vGapSm,
            _row(context, 'GST & Taxes', summary.gstAmount.asCurrency),
          ],
          if (summary.feesTotal > 0) ...[
            AppSpacing.vGapSm,
            _row(context, 'Fees & Charges', summary.feesTotal.asCurrency),
          ],
          if (summary.couponDiscount > 0) ...[
            AppSpacing.vGapSm,
            _row(context, 'Coupon Discount', '- ${summary.couponDiscount.asCurrency}',
                color: vs.success),
          ],
          const Divider(height: AppSpacing.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Grand Total', style: AppTypography.titleLarge),
              Text(summary.total.asCurrency, style: AppTypography.priceLarge),
            ],
          ),
        ],
      ),
    );
  }

  static const _deliveryFeeLabel = '45';

  Widget _row(BuildContext context, String label, String value,
      {Color? color, String? strike}) {
    final vs = context.vsColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary)),
        Row(
          children: [
            if (strike != null) ...[
              Text(strike,
                  style: AppTypography.bodySmall.copyWith(
                    color: vs.textSecondary,
                    decoration: TextDecoration.lineThrough,
                  )),
              AppSpacing.hGapSm,
            ],
            Text(value,
                style: AppTypography.labelLarge
                    .copyWith(color: color ?? context.colors.onSurface)),
          ],
        ),
      ],
    );
  }
}

/// Sticky checkout footer with the payable total and a CTA.
class VSCartFooter extends StatelessWidget {
  const VSCartFooter({
    super.key,
    required this.total,
    required this.enabled,
    required this.onCheckout,
    this.label = 'Checkout securely',
  });

  final num total;
  final bool enabled;
  final VoidCallback onCheckout;
  final String label;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: vs.border)),
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
              child: VSButton(
                label: label,
                trailingIcon: Icons.arrow_forward_rounded,
                onPressed: enabled ? onCheckout : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty-cart state with a CTA back to shopping.
class VSEmptyCart extends StatelessWidget {
  const VSEmptyCart({super.key, required this.onStartShopping});

  final VoidCallback onStartShopping;

  @override
  Widget build(BuildContext context) {
    return VSEmptyState(
      title: 'Your cart is empty',
      message: 'Browse products and add items to get started.',
      icon: Icons.shopping_cart_outlined,
      actionLabel: 'Start Shopping',
      onAction: onStartShopping,
    );
  }
}
