import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../domain/entities/product_filter.dart';

/// Shows the sort options sheet and returns the chosen [ProductSort] (or null).
Future<ProductSort?> showVSSortBottomSheet(
  BuildContext context,
  ProductSort current,
) {
  return showModalBottomSheet<ProductSort>(
    context: context,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      final vs = ctx.vsColors;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: AppSpacing.sm),
              height: 4,
              width: 40,
              decoration: BoxDecoration(
                color: vs.border,
                borderRadius: AppRadius.brPill,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Sort by', style: AppTypography.titleLarge),
              ),
            ),
            for (final sort in ProductSort.values)
              ListTile(
                leading: Icon(
                  sort == current
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: sort == current ? vs.brand : vs.textSecondary,
                ),
                title: Text(sort.label, style: AppTypography.bodyLarge),
                onTap: () => Navigator.of(ctx).pop(sort),
              ),
            AppSpacing.vGapMd,
          ],
        ),
      );
    },
  );
}
