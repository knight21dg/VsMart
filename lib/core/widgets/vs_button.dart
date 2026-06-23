import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

/// Visual variants for [VSButton].
enum VSButtonVariant { primary, secondary, danger, neutral }

enum VSButtonSize { small, medium, large }

/// Primary filled CTA button for VS Mart with loading and icon support.
class VSButton extends StatelessWidget {
  const VSButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = VSButtonVariant.primary,
    this.size = VSButtonSize.large,
    this.isLoading = false,
    this.isExpanded = true,
    this.icon,
    this.trailingIcon,
  });

  final String label;
  final VoidCallback? onPressed;
  final VSButtonVariant variant;
  final VSButtonSize size;
  final bool isLoading;
  final bool isExpanded;
  final IconData? icon;
  final IconData? trailingIcon;

  Color _bg() => switch (variant) {
        VSButtonVariant.primary => AppColors.vsGreen,
        VSButtonVariant.secondary => AppColors.trustBlue,
        VSButtonVariant.danger => AppColors.error,
        VSButtonVariant.neutral => AppColors.textPrimary,
      };

  double _height() => switch (size) {
        VSButtonSize.small => 40,
        VSButtonSize.medium => 48,
        VSButtonSize.large => 52,
      };

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || isLoading;

    final child = isLoading
        ? const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation(AppColors.white),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20),
                AppSpacing.hGapSm,
              ],
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge,
                ),
              ),
              if (trailingIcon != null) ...[
                AppSpacing.hGapSm,
                Icon(trailingIcon, size: 20),
              ],
            ],
          );

    final button = ElevatedButton(
      onPressed: disabled ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: _bg(),
        foregroundColor: AppColors.white,
        disabledBackgroundColor: AppColors.disabled,
        minimumSize: Size(isExpanded ? double.infinity : 0, _height()),
        padding: EdgeInsets.symmetric(
          horizontal: size == VSButtonSize.small ? AppSpacing.lg : AppSpacing.xl,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
        elevation: 0,
      ),
      child: child,
    );

    return isExpanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}
