import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';

/// Reusable full-screen "no internet" state for screens that have nothing cached
/// to show while offline. Pair with [VSOfflineBanner] for screens that CAN
/// render stale cache.
class NoInternetView extends StatelessWidget {
  const NoInternetView({super.key, this.onRetry, this.scaffold = false});

  final VoidCallback? onRetry;

  /// Wrap in a [Scaffold] when used as a standalone screen.
  final bool scaffold;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final body = Center(
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
                shape: BoxShape.circle,
              ),
              child:
                  Icon(Icons.wifi_off_rounded, size: 44, color: vs.danger),
            ),
            AppSpacing.vGapXl,
            Text('No Internet Connection',
                textAlign: TextAlign.center,
                style: AppTypography.headlineSmall),
            AppSpacing.vGapSm,
            Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
            ),
            if (onRetry != null) ...[
              AppSpacing.vGapXl,
              VSButton(
                label: 'Retry',
                icon: Icons.refresh_rounded,
                isExpanded: false,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
    return scaffold ? Scaffold(body: SafeArea(child: body)) : body;
  }
}
