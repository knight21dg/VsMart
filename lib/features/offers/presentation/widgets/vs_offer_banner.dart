import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../domain/entities/offer.dart';

/// Promotional banner card for the home carousel. Renders an [Offer] with a
/// badge, headline, subtitle and optional coupon code.
class VSOfferBanner extends StatelessWidget {
  const VSOfferBanner({super.key, required this.offer, this.onTap});

  final Offer offer;
  final VoidCallback? onTap;

  // Rotate gradients so consecutive banners read as distinct.
  static const _gradients = [
    AppColors.offerGradient,
    AppColors.creditGradient,
    AppColors.greenGradient,
  ];

  @override
  Widget build(BuildContext context) {
    final gradient = _gradients[offer.id.hashCode.abs() % _gradients.length];
    final faint = AppColors.white.withValues(alpha: 0.9);
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brXl,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(gradient: gradient, borderRadius: AppRadius.brXl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (offer.badge != null)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.22),
                  borderRadius: AppRadius.brSm,
                ),
                child: Text(offer.badge!,
                    style: AppTypography.labelSmall
                        .copyWith(color: AppColors.white)),
              ),
            AppSpacing.vGapSm,
            Text(offer.title,
                style: AppTypography.headlineLarge
                    .copyWith(color: AppColors.white)),
            if (offer.subtitle.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(offer.subtitle,
                  style: AppTypography.bodyMedium.copyWith(color: faint)),
            ],
            if (offer.code != null) ...[
              AppSpacing.vGapSm,
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.18),
                  borderRadius: AppRadius.brSm,
                  border: Border.all(color: AppColors.white.withValues(alpha: 0.4)),
                ),
                child: Text('Code: ${offer.code}',
                    style: AppTypography.labelMedium
                        .copyWith(color: AppColors.white)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
