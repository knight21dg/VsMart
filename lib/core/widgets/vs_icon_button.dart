import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../extensions/context_extensions.dart';

/// Square, rounded icon button used for app-bar actions, cart steppers, etc.
/// Optionally renders a small notification [badgeCount].
class VSIconButton extends StatelessWidget {
  const VSIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 44,
    this.iconSize = 22,
    this.background,
    this.iconColor,
    this.badgeCount,
    this.tooltip,
    this.bordered = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color? background;
  final Color? iconColor;
  final int? badgeCount;
  final String? tooltip;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final bg = background ?? context.colors.surface;

    final button = Material(
      color: bg,
      borderRadius: AppRadius.brMd,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          height: size,
          width: size,
          alignment: Alignment.center,
          decoration: bordered
              ? BoxDecoration(
                  borderRadius: AppRadius.brMd,
                  border: Border.all(color: vs.border),
                )
              : null,
          child: Icon(
            icon,
            size: iconSize,
            color: iconColor ?? context.textStyles.bodyLarge?.color,
          ),
        ),
      ),
    );

    final content = (badgeCount != null && badgeCount! > 0)
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              button,
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 18),
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.rectangle,
                    borderRadius: AppRadius.brPill,
                  ),
                  child: Text(
                    badgeCount! > 99 ? '99+' : '$badgeCount',
                    textAlign: TextAlign.center,
                    style: AppTypography.labelSmall
                        .copyWith(color: AppColors.white, fontSize: 10),
                  ),
                ),
              ),
            ],
          )
        : button;

    return tooltip == null
        ? content
        : Tooltip(message: tooltip!, child: content);
  }
}
