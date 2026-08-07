import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../providers/system_providers.dart';

/// Full-screen gate shown when the installed version is below the backend's
/// `minAppVersion`. Blocking — the user must update to continue.
class ForceUpdateScreen extends ConsumerWidget {
  const ForceUpdateScreen({super.key});

  /// Android applicationId (see android/app/build.gradle.kts). Kept in sync
  /// manually — the Play Store listing is keyed on this id.
  static const String _androidPackageId = 'com.vsmart.user_app';

  /// Open the Play Store on the app's listing: try the native `market://` deep
  /// link first (opens the Play Store app directly), then fall back to the
  /// https web URL. Fails gracefully with a snackbar if neither can launch.
  Future<void> _openStore(BuildContext context) async {
    final market = Uri.parse('market://details?id=$_androidPackageId');
    final web = Uri.parse(
        'https://play.google.com/store/apps/details?id=$_androidPackageId');
    try {
      if (await launchUrl(market, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {
      // Play Store app not installed / no handler — fall through to the web URL.
    }
    try {
      if (await launchUrl(web, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {
      // No browser to handle the web URL either.
    }
    if (context.mounted) {
      context.showSnack(context.l10n.systemPlayStoreError);
    }
  }

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
                Text(context.l10n.systemUpdateTitle,
                    textAlign: TextAlign.center,
                    style: AppTypography.headlineMedium),
                AppSpacing.vGapSm,
                Text(
                  context.l10n.systemUpdateBody,
                  textAlign: TextAlign.center,
                  style:
                      AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
                ),
                AppSpacing.vGapXl,
                VSButton(
                  label: context.l10n.systemUpdateNow,
                  icon: Icons.shop_rounded,
                  onPressed: () => _openStore(context),
                ),
                AppSpacing.vGapMd,
                VSOutlinedButton(
                  label: context.l10n.systemUpdatedCheckAgain,
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
