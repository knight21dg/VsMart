import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

/// Promotional banner card for the offers carousel / home rail.
class VSOfferCard extends StatelessWidget {
  const VSOfferCard({
    super.key,
    required this.title,
    this.subtitle,
    this.code,
    this.imageUrl,
    this.gradient,
    this.width = 300,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final String? code;
  final String? imageUrl;
  final Gradient? gradient;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brLg,
      child: Container(
        width: width,
        height: 140,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: gradient ?? AppColors.offerGradient,
          borderRadius: AppRadius.brLg,
        ),
        child: Stack(
          children: [
            if (imageUrl != null)
              Positioned(
                right: -10,
                bottom: -10,
                child: Image.network(
                  imageUrl!,
                  height: 130,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.headlineSmall
                            .copyWith(color: AppColors.white),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmall.copyWith(
                              color: AppColors.white.withValues(alpha: 0.9)),
                        ),
                      ],
                    ],
                  ),
                  if (code != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: AppColors.white.withValues(alpha: 0.25),
                        borderRadius: AppRadius.brSm,
                      ),
                      child: Text(
                        'CODE: $code',
                        style: AppTypography.labelMedium
                            .copyWith(color: AppColors.white),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
