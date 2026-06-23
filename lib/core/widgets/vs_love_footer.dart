import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../extensions/context_extensions.dart';

/// Warm sign-off shown at the very bottom of long scrolling pages
/// (Home, Categories, Account…). Renders a centered "With Love, VS Mart ❤️"
/// wordmark with a subtle divider so the catalog feels like it has an end.
class VSLoveFooter extends StatelessWidget {
  const VSLoveFooter({super.key, this.tagline = 'Fresh groceries • Shop now, pay later'});

  /// Optional tiny line beneath the wordmark. Pass an empty string to hide it.
  final String tagline;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xxl,
        AppSpacing.xl,
        AppSpacing.xxl,
      ),
      child: Column(
        children: [
          // Thin centered divider with a heart in the middle.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: 56,
                    child: Divider(color: vs.border, thickness: 1),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Icon(Icons.favorite_rounded,
                    size: 16, color: AppColors.error),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 56,
                    child: Divider(color: vs.border, thickness: 1),
                  ),
                ),
              ),
            ],
          ),
          AppSpacing.vGapMd,
          Text.rich(
            TextSpan(
              text: 'With Love, ',
              style: AppTypography.titleMedium.copyWith(
                color: vs.textSecondary,
                fontWeight: FontWeight.w500,
              ),
              children: [
                TextSpan(
                  text: 'VS Mart',
                  style: AppTypography.titleMedium.copyWith(
                    color: vs.brand,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const TextSpan(text: '  ❤️'),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          if (tagline.isNotEmpty) ...[
            AppSpacing.vGapXs,
            Text(
              tagline,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: vs.textSecondary.withValues(alpha: 0.8),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
