import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../extensions/context_extensions.dart';
import 'vs_network_image.dart';

/// Compact category tile (icon/image + label) for category grids and rails.
class VSCategoryCard extends StatelessWidget {
  const VSCategoryCard({
    super.key,
    required this.label,
    this.imageUrl,
    this.icon,
    this.backgroundColor,
    this.onTap,
  });

  final String label;
  final String? imageUrl;
  final IconData? icon;
  final Color? backgroundColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brMd,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 64,
            width: 64,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: backgroundColor ?? vs.brandTint,
              borderRadius: AppRadius.brLg,
            ),
            // Treat an empty url as "no image": the backend sends "" for a
            // category with no artwork, which would otherwise render as a
            // permanently broken image instead of the icon fallback.
            child: (imageUrl != null && imageUrl!.isNotEmpty)
                ? VSNetworkImage(
                    url: imageUrl,
                    fit: BoxFit.contain,
                    borderRadius: AppRadius.brSm,
                  )
                : Icon(icon ?? Icons.category_rounded, color: vs.brand),
          ),
          AppSpacing.vGapSm,
          SizedBox(
            width: 72,
            child: Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}
