import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../errors/failures.dart';
import '../extensions/context_extensions.dart';
import 'vs_outlined_button.dart';

/// Standard error state with a retry action. Accepts a raw [message] or a
/// domain [failure].
class VSErrorView extends StatelessWidget {
  const VSErrorView({
    super.key,
    this.message,
    this.failure,
    this.onRetry,
    this.icon = Icons.cloud_off_rounded,
  });

  final String? message;
  final Failure? failure;
  final VoidCallback? onRetry;
  final IconData icon;

  String get _text =>
      message ?? failure?.message ?? 'Something went wrong. Please try again.';

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 96,
              width: 96,
              decoration: BoxDecoration(
                color: vs.dangerTint,
                borderRadius: AppRadius.brXxl,
              ),
              child: Icon(icon, size: 44, color: vs.danger),
            ),
            AppSpacing.vGapXl,
            Text('Oops!',
                textAlign: TextAlign.center,
                style: AppTypography.headlineSmall),
            AppSpacing.vGapSm,
            Text(
              _text,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
            ),
            if (onRetry != null) ...[
              AppSpacing.vGapXl,
              VSOutlinedButton(
                label: 'Try Again',
                icon: Icons.refresh_rounded,
                isExpanded: false,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
