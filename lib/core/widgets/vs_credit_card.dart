import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../extensions/num_extensions.dart';

/// Hero credit-summary card for the Credit Dashboard: available credit, used,
/// limit, and an optional due amount.
class VSCreditCard extends StatelessWidget {
  const VSCreditCard({
    super.key,
    required this.availableCredit,
    required this.creditLimit,
    this.usedCredit = 0,
    this.dueAmount,
    this.dueDateLabel,
    this.onPayNow,
    this.onViewDetails,
  });

  final num availableCredit;
  final num creditLimit;
  final num usedCredit;
  final num? dueAmount;
  final String? dueDateLabel;
  final VoidCallback? onPayNow;
  final VoidCallback? onViewDetails;

  @override
  Widget build(BuildContext context) {
    final usedRatio =
        creditLimit <= 0 ? 0.0 : (usedCredit / creditLimit).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: AppColors.creditGradient,
        borderRadius: AppRadius.brXl,
        boxShadow: AppShadows.glow(AppColors.trustBlue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Available Credit',
                  style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.white.withValues(alpha: 0.85))),
              const Icon(Icons.account_balance_wallet_rounded,
                  color: AppColors.white),
            ],
          ),
          AppSpacing.vGapSm,
          Text(availableCredit.asCurrency,
              style: AppTypography.displayMedium
                  .copyWith(color: AppColors.white)),
          AppSpacing.vGapLg,
          ClipRRect(
            borderRadius: AppRadius.brPill,
            child: LinearProgressIndicator(
              value: usedRatio,
              minHeight: 8,
              backgroundColor: AppColors.white.withValues(alpha: 0.25),
              valueColor: const AlwaysStoppedAnimation(AppColors.white),
            ),
          ),
          AppSpacing.vGapSm,
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Used ${usedCredit.asCurrency}',
                  style: AppTypography.bodySmall.copyWith(
                      color: AppColors.white.withValues(alpha: 0.85))),
              Text('Limit ${creditLimit.asCurrency}',
                  style: AppTypography.bodySmall.copyWith(
                      color: AppColors.white.withValues(alpha: 0.85))),
            ],
          ),
          if (dueAmount != null && dueAmount! > 0) ...[
            AppSpacing.vGapLg,
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.white.withValues(alpha: 0.15),
                borderRadius: AppRadius.brMd,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Amount Due',
                            style: AppTypography.bodySmall.copyWith(
                                color:
                                    AppColors.white.withValues(alpha: 0.85))),
                        Text(dueAmount!.asCurrency,
                            style: AppTypography.priceMedium
                                .copyWith(color: AppColors.white)),
                        if (dueDateLabel != null)
                          Text('Due $dueDateLabel',
                              style: AppTypography.labelSmall.copyWith(
                                  color: AppColors.white
                                      .withValues(alpha: 0.85))),
                      ],
                    ),
                  ),
                  if (onPayNow != null)
                    FilledButton(
                      onPressed: onPayNow,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.white,
                        foregroundColor: AppColors.trustBlue,
                        shape: const RoundedRectangleBorder(
                            borderRadius: AppRadius.brSm),
                      ),
                      child: const Text('Pay Now'),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
