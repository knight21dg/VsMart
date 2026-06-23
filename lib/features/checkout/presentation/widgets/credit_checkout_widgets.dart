import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';

/// Credit breakdown shown when paying on VS Credit: limit, used, available,
/// purchase amount, and remaining credit after this order.
class VSCreditCheckoutCard extends StatelessWidget {
  const VSCreditCheckoutCard({
    super.key,
    required this.creditLimit,
    required this.outstanding,
    required this.purchaseAmount,
  });

  final num creditLimit;
  final num outstanding;
  final num purchaseAmount;

  num get _available {
    final a = creditLimit - outstanding;
    return a < 0 ? 0 : a;
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final remaining = _available - purchaseAmount;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: vs.trustTint.withValues(alpha: 0.5),
        borderRadius: AppRadius.brMd,
      ),
      child: Column(
        children: [
          _row(context, 'Credit Limit', creditLimit.asCurrency),
          AppSpacing.vGapXs,
          _row(context, 'Used Credit', outstanding.asCurrency),
          AppSpacing.vGapXs,
          _row(context, 'Available Credit', _available.asCurrency),
          AppSpacing.vGapXs,
          _row(context, 'Purchase Amount', '- ${purchaseAmount.asCurrency}'),
          const Divider(height: AppSpacing.lg),
          _row(
            context,
            'Remaining Credit',
            (remaining < 0 ? 0 : remaining).asCurrency,
            bold: true,
            color: remaining < 0 ? vs.danger : null,
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value,
      {bool bold = false, Color? color}) {
    final vs = context.vsColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary)),
        Text(value,
            style: bold
                ? AppTypography.labelLarge.copyWith(color: color)
                : AppTypography.bodyMedium
                    .copyWith(color: color ?? context.colors.onSurface)),
      ],
    );
  }
}

/// Eligibility banner for credit payment: confirms availability or shows the
/// shortfall when credit is insufficient.
class VSCreditEligibilityBanner extends StatelessWidget {
  const VSCreditEligibilityBanner({
    super.key,
    required this.available,
    required this.amount,
  });

  final num available;
  final num amount;

  bool get _eligible => available >= amount;
  num get _shortfall => amount - available;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final color = _eligible ? vs.success : vs.danger;
    final bg = _eligible ? vs.successTint : vs.dangerTint;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.brMd),
      child: Row(
        children: [
          Icon(
            _eligible ? Icons.verified_rounded : Icons.error_outline_rounded,
            size: 18,
            color: color,
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Text(
              _eligible
                  ? 'Eligible — ${available.asCurrency} credit available'
                  : 'Insufficient credit — short by ${_shortfall.asCurrency}',
              style: AppTypography.labelMedium.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
