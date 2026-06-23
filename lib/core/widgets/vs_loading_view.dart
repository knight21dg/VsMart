import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../extensions/context_extensions.dart';

/// Centered loading indicator with an optional message.
class VSLoadingView extends StatelessWidget {
  const VSLoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.vsGreen),
          if (message != null) ...[
            AppSpacing.vGapLg,
            Text(
              message!,
              style: AppTypography.bodyMedium
                  .copyWith(color: context.vsColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Full-screen blocking overlay (e.g. while submitting a payment).
class VSLoadingOverlay extends StatelessWidget {
  const VSLoadingOverlay({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.overlay,
      child: VSLoadingView(message: message),
    );
  }
}
