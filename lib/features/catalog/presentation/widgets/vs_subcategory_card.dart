import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';

/// Card for a sub-category in the drill-down grid: thumbnail/icon, name and a
/// product count.
class VSSubCategoryCard extends StatelessWidget {
  const VSSubCategoryCard({
    super.key,
    required this.name,
    required this.productCount,
    this.icon = Icons.category_rounded,
    this.imageUrl,
    this.onTap,
  });

  final String name;
  final int productCount;
  final IconData icon;
  final String? imageUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brLg,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: AppRadius.brLg,
          border: Border.all(color: vs.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 56,
              width: 56,
              decoration:
                  BoxDecoration(color: vs.brandTint, shape: BoxShape.circle),
              clipBehavior: Clip.antiAlias,
              child: imageUrl != null
                  ? VSNetworkImage(url: imageUrl, fit: BoxFit.cover)
                  : Icon(icon, color: vs.brand, size: 26),
            ),
            AppSpacing.vGapSm,
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelLarge,
            ),
            const SizedBox(height: 2),
            Text('$productCount items',
                style:
                    AppTypography.labelSmall.copyWith(color: vs.textSecondary)),
          ],
        ),
      ),
    );
  }
}
