import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../extensions/context_extensions.dart';

/// Outlined / secondary action button matching [VSButton]'s metrics.
class VSOutlinedButton extends StatelessWidget {
  const VSOutlinedButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.isExpanded = true,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool isExpanded;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.vsColors.brand;
    final disabled = onPressed == null || isLoading;

    final child = isLoading
        ? SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation(c),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[Icon(icon, size: 20), AppSpacing.hGapSm],
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge),
              ),
            ],
          );

    final button = OutlinedButton(
      onPressed: disabled ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: c,
        minimumSize: Size(isExpanded ? double.infinity : 0, 52),
        side: BorderSide(color: disabled ? AppColors.disabled : c, width: 1.5),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
      ),
      child: child,
    );

    return isExpanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}
