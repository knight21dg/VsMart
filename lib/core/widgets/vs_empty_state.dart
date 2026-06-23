import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../extensions/context_extensions.dart';
import 'vs_button.dart';

/// Friendly empty-state placeholder with optional illustration and CTA.
class VSEmptyState extends StatelessWidget {
  const VSEmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.illustrationAsset,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? message;
  final IconData icon;
  final String? illustrationAsset;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (illustrationAsset != null)
              Image.asset(illustrationAsset!, height: 160)
            else
              Container(
                height: 96,
                width: 96,
                decoration: BoxDecoration(
                  color: vs.brandTint,
                  borderRadius: AppRadius.brXxl,
                ),
                child: Icon(icon, size: 44, color: vs.brand),
              ),
            AppSpacing.vGapXl,
            Text(title,
                textAlign: TextAlign.center,
                style: AppTypography.headlineSmall),
            if (message != null) ...[
              AppSpacing.vGapSm,
              Text(
                message!,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium
                    .copyWith(color: vs.textSecondary),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              AppSpacing.vGapXl,
              VSButton(
                label: actionLabel!,
                onPressed: onAction,
                isExpanded: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
