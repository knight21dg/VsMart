import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../providers/system_providers.dart';

/// Full-screen gate shown while the backend is in maintenance mode. Blocking by
/// design — "Try Again" re-fetches `/app-config`.
class MaintenanceScreen extends ConsumerWidget {
  const MaintenanceScreen({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 96,
                  width: 96,
                  decoration: BoxDecoration(
                    color: vs.offerTint,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.build_rounded, size: 44, color: vs.offer),
                ),
                AppSpacing.vGapXl,
                Text('Under Maintenance',
                    textAlign: TextAlign.center,
                    style: AppTypography.headlineMedium),
                AppSpacing.vGapSm,
                Text(
                  message?.isNotEmpty == true
                      ? message!
                      : "We're sprucing things up and will be back shortly. "
                          'Thanks for your patience.',
                  textAlign: TextAlign.center,
                  style:
                      AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
                ),
                AppSpacing.vGapXl,
                VSButton(
                  label: 'Try Again',
                  icon: Icons.refresh_rounded,
                  isExpanded: false,
                  onPressed: () => ref.invalidate(appStatusProvider),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
