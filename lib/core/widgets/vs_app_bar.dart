import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../extensions/context_extensions.dart';

/// Standard VS Mart app bar with optional back button and action widgets.
class VSAppBar extends StatelessWidget implements PreferredSizeWidget {
  const VSAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.showBack = true,
    this.onBack,
    this.centerTitle = false,
    this.bottom,
    this.backgroundColor,
    this.leading,
  });

  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final bool showBack;
  final VoidCallback? onBack;
  final bool centerTitle;
  final PreferredSizeWidget? bottom;
  final Color? backgroundColor;
  final Widget? leading;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return AppBar(
      backgroundColor: backgroundColor,
      centerTitle: centerTitle,
      automaticallyImplyLeading: false,
      titleSpacing: showBack && (canPop || onBack != null) ? 0 : AppSpacing.lg,
      leading: leading ??
          (showBack && (canPop || onBack != null)
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                )
              : null),
      title: titleWidget ??
          (title != null
              ? Text(title!, style: AppTypography.headlineSmall.copyWith(
                  color: context.textStyles.bodyLarge?.color))
              : null),
      actions: actions == null
          ? null
          : [
              ...actions!,
              const SizedBox(width: AppSpacing.sm),
            ],
      bottom: bottom,
    );
  }
}
