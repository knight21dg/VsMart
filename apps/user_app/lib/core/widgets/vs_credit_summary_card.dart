import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../extensions/num_extensions.dart';

/// Compact credit summary card: available credit, VS score, outstanding + due,
/// and a Pay Now CTA. Reused on Home, Credit Dashboard, Checkout and Profile.
class VSCreditSummaryCard extends StatelessWidget {
  const VSCreditSummaryCard({
    super.key,
    required this.availableCredit,
    required this.vsScore,
    required this.outstanding,
    required this.dueDateLabel,
    this.onPayNow,
  });

  final num availableCredit;
  final int vsScore;
  final num outstanding;
  final String dueDateLabel;
  final VoidCallback? onPayNow;

  static const LinearGradient _gradient = LinearGradient(
    colors: [AppColors.vsGreen, AppColors.trustBlue],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  @override
  Widget build(BuildContext context) {
    final onCredit = AppColors.white.withValues(alpha: 0.85);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: _gradient,
        borderRadius: AppRadius.brXl,
        boxShadow: AppShadows.glow(AppColors.trustBlue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Available Credit',
                        style: AppTypography.bodySmall.copyWith(color: onCredit)),
                    const SizedBox(height: 2),
                    Text(availableCredit.asCurrency,
                        style: AppTypography.displayMedium
                            .copyWith(color: AppColors.white)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.18),
                  borderRadius: AppRadius.brPill,
                ),
                child: Column(
                  children: [
                    Text('VS Score',
                        style: AppTypography.labelSmall.copyWith(color: onCredit)),
                    Text('$vsScore',
                        style: AppTypography.titleLarge
                            .copyWith(color: AppColors.white)),
                  ],
                ),
              ),
            ],
          ),
          AppSpacing.vGapLg,
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Outstanding · due $dueDateLabel',
                        style: AppTypography.bodySmall.copyWith(color: onCredit)),
                    const SizedBox(height: 2),
                    Text(outstanding.asCurrency,
                        style: AppTypography.priceMedium
                            .copyWith(color: AppColors.white)),
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
                        borderRadius: AppRadius.brMd),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                      vertical: AppSpacing.md,
                    ),
                  ),
                  child: Text('Pay Now',
                      style: AppTypography.labelLarge
                          .copyWith(color: AppColors.trustBlue)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
