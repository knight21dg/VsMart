import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../extensions/context_extensions.dart';

/// Semantic tone for [VSStatusChip].
enum VSStatusTone { neutral, success, warning, danger, info, brand, offer }

/// Compact pill that conveys a status (order state, credit health, etc.).
class VSStatusChip extends StatelessWidget {
  const VSStatusChip({
    super.key,
    required this.label,
    this.tone = VSStatusTone.neutral,
    this.icon,
    this.dense = false,
  });

  final String label;
  final VSStatusTone tone;
  final IconData? icon;
  final bool dense;

  ({Color fg, Color bg}) _colors(BuildContext context) {
    final vs = context.vsColors;
    return switch (tone) {
      VSStatusTone.success => (fg: vs.success, bg: vs.successTint),
      VSStatusTone.warning => (fg: vs.warning, bg: AppColors.amberTint),
      VSStatusTone.danger => (fg: vs.danger, bg: vs.dangerTint),
      VSStatusTone.info => (fg: vs.trust, bg: vs.trustTint),
      VSStatusTone.brand => (fg: vs.brand, bg: vs.brandTint),
      VSStatusTone.offer => (fg: vs.offer, bg: vs.offerTint),
      VSStatusTone.neutral => (fg: vs.textSecondary, bg: context.colors.surface),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = _colors(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AppSpacing.sm : AppSpacing.md,
        vertical: dense ? 2 : AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: AppRadius.brPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 12 : 14, color: c.fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: (dense ? AppTypography.labelSmall : AppTypography.labelMedium)
                .copyWith(color: c.fg),
          ),
        ],
      ),
    );
  }
}
