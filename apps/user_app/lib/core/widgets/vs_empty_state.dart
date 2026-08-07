import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../extensions/context_extensions.dart';
import 'vs_button.dart';

/// Friendly empty-state placeholder with a layered icon medallion and optional
/// CTA. Fades and lifts in gently so an empty screen reads as intentional rather
/// than broken. The [accent] recolors the medallion (defaults to the brand
/// green); pass a semantic color for context — e.g. offer orange for "no deals".
class VSEmptyState extends StatelessWidget {
  const VSEmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_rounded,
    this.illustrationAsset,
    this.actionLabel,
    this.onAction,
    this.accent,
  });

  final String title;
  final String? message;
  final IconData icon;
  final String? illustrationAsset;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final accent = this.accent ?? vs.brand;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, (1 - t) * 16),
              child: child,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (illustrationAsset != null)
                Image.asset(illustrationAsset!, height: 168)
              else
                _Medallion(icon: icon, accent: accent),
              AppSpacing.vGapXl,
              Text(title,
                  textAlign: TextAlign.center,
                  style: AppTypography.headlineSmall),
              if (message != null) ...[
                AppSpacing.vGapSm,
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium
                        .copyWith(color: vs.textSecondary, height: 1.5),
                  ),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                AppSpacing.vGapXl,
                VSButton(
                  label: actionLabel!,
                  onPressed: onAction,
                  icon: Icons.arrow_forward_rounded,
                  isExpanded: false,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Concentric soft rings behind a tinted disc holding the glyph.
class _Medallion extends StatelessWidget {
  const _Medallion({required this.icon, required this.accent});

  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      width: 132,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _ring(132, accent.withValues(alpha: 0.08)),
          _ring(108, accent.withValues(alpha: 0.12)),
          Container(
            height: 84,
            width: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  accent.withValues(alpha: 0.22),
                  accent.withValues(alpha: 0.12),
                ],
              ),
            ),
            child: Icon(icon, size: 38, color: accent),
          ),
        ],
      ),
    );
  }

  Widget _ring(double size, Color color) => Container(
        height: size,
        width: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
}
