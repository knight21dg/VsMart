import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';

/// The handover code, made impossible to miss.
///
/// The OTP used to reach the customer only as an in-app notification — buried in
/// the inbox at the exact moment a rider stood at the door asking for it. It now
/// renders wherever the customer already is: the tracking screen, the order
/// details page, and the profile's arriving-order banner.
class DeliveryOtpCard extends StatelessWidget {
  const DeliveryOtpCard({super.key, required this.code, this.compact = false});

  final String code;

  /// Tighter paddings for embedding inside list rows/banners.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: compact ? AppSpacing.sm : AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: vs.brandTint,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.brand.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.key_rounded, color: vs.brand),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.deliveryOtpTitle,
                    style: AppTypography.labelLarge),
                Text(
                  context.l10n.deliveryOtpShare,
                  style: AppTypography.bodySmall
                      .copyWith(color: vs.textSecondary),
                ),
              ],
            ),
          ),
          AppSpacing.hGapMd,
          Text(
            code,
            style: AppTypography.headlineSmall.copyWith(
              color: vs.brand,
              fontWeight: FontWeight.w800,
              letterSpacing: 4,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
