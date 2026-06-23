import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../providers/system_providers.dart';

/// Full-screen gate shown when the installed version is below the backend's
/// `minAppVersion`. Blocking — the user must update to continue.
class ForceUpdateScreen extends ConsumerWidget {
  const ForceUpdateScreen({super.key});

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
                    color: vs.brandTint,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.system_update_rounded,
                      size: 44, color: vs.brand),
                ),
                AppSpacing.vGapXl,
                Text('Update Required',
                    textAlign: TextAlign.center,
                    style: AppTypography.headlineMedium),
                AppSpacing.vGapSm,
                Text(
                  'A newer version of VS Mart is available with important '
                  'improvements. Please update from the Play Store to continue.',
                  textAlign: TextAlign.center,
                  style:
                      AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
                ),
                AppSpacing.vGapXl,
                VSButton(
                  label: 'Update Now',
                  icon: Icons.shop_rounded,
                  onPressed: () =>
                      context.showSnack('Open the Play Store to update VS Mart.'),
                ),
                AppSpacing.vGapMd,
                VSOutlinedButton(
                  label: "I've updated — Check again",
                  icon: Icons.refresh_rounded,
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
