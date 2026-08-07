import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';

/// A pill chip used for filter toggles, sort/filter entry points, and removable
/// active-filter chips (when [onRemove] is provided).
class VSFilterChip extends StatelessWidget {
  const VSFilterChip({
    super.key,
    required this.label,
    this.selected = false,
    this.icon,
    this.onTap,
    this.onRemove,
  });

  final String label;
  final bool selected;
  final IconData? icon;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brPill,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? vs.brandTint : context.colors.surface,
          borderRadius: AppRadius.brPill,
          border: Border.all(color: selected ? vs.brand : vs.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: selected ? vs.brand : vs.textSecondary),
              const SizedBox(width: AppSpacing.xs),
            ],
            Text(
              label,
              style: AppTypography.labelMedium.copyWith(
                color: selected ? vs.brand : null,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            if (onRemove != null) ...[
              const SizedBox(width: AppSpacing.xs),
              GestureDetector(
                onTap: onRemove,
                child: Icon(Icons.close_rounded, size: 14, color: vs.brand),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
