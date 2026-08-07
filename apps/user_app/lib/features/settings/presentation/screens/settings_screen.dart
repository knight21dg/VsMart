import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/constants/api_constants.dart';
import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/app_error_presenter.dart';
import '../../../../core/errors/error_handler.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../../shared/providers/settings_provider.dart';
import '../../../address/presentation/providers/address_providers.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/providers/session_provider.dart';

/// App settings — matches the design: grouped plain-icon rows for account, app
/// preferences, security, credit and legal, plus a logout / delete-account card.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  String _themeLabel(BuildContext context, ThemeMode m) => switch (m) {
        ThemeMode.system => context.l10n.settingsSystemDefault,
        ThemeMode.light => context.l10n.settingsLightMode,
        ThemeMode.dark => context.l10n.settingsDarkMode,
      };

  Future<void> _pickTheme(BuildContext context, WidgetRef ref) async {
    final current = ref.read(themeModeProvider);
    final picked = await showModalBottomSheet<ThemeMode>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text(context.l10n.settingsTheme,
                  style: AppTypography.titleLarge),
            ),
            for (final m in ThemeMode.values)
              RadioListTile<ThemeMode>(
                value: m,
                groupValue: current,
                activeColor: AppColors.vsGreen,
                title: Text(_themeLabel(context, m)),
                onChanged: (v) => Navigator.of(ctx).pop(v),
              ),
            AppSpacing.vGapSm,
          ],
        ),
      ),
    );
    if (picked != null) await ref.read(themeModeProvider.notifier).set(picked);
  }

  Future<void> _confirm(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String body,
    required String confirmLabel,
    required VoidCallback onConfirm,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    if (ok == true) onConfirm();
  }

  /// Submit a compliant account-deletion REQUEST to the backend, then sign the
  /// user out. The public endpoint (keyed on the account's email or phone)
  /// records the request for ops to process — this is not an instant delete, and
  /// the confirmation copy is written to match.
  Future<void> _requestAccountDeletion(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final user = ref.read(sessionControllerProvider).user;
    final email = user?.email?.trim() ?? '';
    final contact = email.isNotEmpty ? email : (user?.phone.trim() ?? '');
    if (contact.isEmpty) {
      context.showSnack(context.l10n.settingsNoAccountContact);
      return;
    }
    try {
      await ref.read(apiClientProvider).post<dynamic>(
        ApiConstants.accountDeletionRequest,
        data: {
          'contact': contact,
          if (user != null && user.name.trim().isNotEmpty)
            'name': user.name.trim(),
        },
        options: ApiClient.noAuth(),
      );
      if (!context.mounted) return;
      context.showSnack(context.l10n.settingsDeletionRequested);
      await ref.read(authControllerProvider.notifier).logout();
    } catch (e) {
      if (!context.mounted) return;
      presentFailure(context, ref, ErrorHandler.handle(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    final themeMode = ref.watch(themeModeProvider);

    Future<void> detectLocation() async {
      final ok =
          await ref.read(addressesProvider.notifier).detectAndSetLocation();
      if (!context.mounted) return;
      context.showSnack(ok
          ? 'Location updated to your current position.'
          : 'Location unavailable. Enable location access in system settings.');
    }

    // NOTE: the "Emergency contact" entry point was removed — it collected a
    // phone number but there is no backend field or local store to persist it,
    // so it silently discarded input. Re-add once an emergency-contact API (or
    // deliberate local storage) exists.

    return Scaffold(
      appBar: VSAppBar(title: context.l10n.settingsTitle),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
          children: [
            _Group(
              title: context.l10n.settingsAccountSettings,
              rows: [
                _SettingsRow(
                  icon: Icons.person_outline_rounded,
                  label: context.l10n.accountEditProfile,
                  onTap: () => context.pushNamed(RouteNames.profile),
                ),
                _SettingsRow(
                  icon: Icons.location_on_outlined,
                  label: context.l10n.profileManageAddresses,
                  onTap: () => context.pushNamed(RouteNames.addresses),
                ),
                _SettingsRow(
                  icon: Icons.verified_user_outlined,
                  label: context.l10n.kycDetailsTitle,
                  onTap: () => context.pushNamed(RouteNames.kycDetails),
                ),
                _SettingsRow(
                  icon: Icons.people_outline_rounded,
                  label: context.l10n.profileFamilyInfo,
                  onTap: () => context.pushNamed(RouteNames.familyInfo),
                ),
              ],
            ),
            _Group(
              title: context.l10n.settingsAppPreferences,
              rows: [
                _SettingsRow(
                  icon: Icons.language_rounded,
                  label: context.l10n.accountLanguage,
                  trailingText: 'English',
                  onTap: () => context.pushNamed(RouteNames.language),
                ),
                _SettingsRow(
                  icon: Icons.wb_sunny_outlined,
                  label: context.l10n.settingsTheme,
                  trailingText: _themeLabel(context, themeMode),
                  onTap: () => _pickTheme(context, ref),
                ),
                _SettingsRow(
                  icon: Icons.notifications_none_rounded,
                  label: context.l10n.settingsNotificationPrefs,
                  onTap: () => context.pushNamed(RouteNames.notificationSettings),
                ),
                _SettingsRow(
                  icon: Icons.my_location_rounded,
                  label: context.l10n.settingsLocationPermissions,
                  onTap: detectLocation,
                ),
              ],
            ),
            _Group(
              title: context.l10n.settingsSecuritySettings,
              rows: [
                _SettingsRow(
                  icon: Icons.security_rounded,
                  label: context.l10n.settingsSecurityAlerts,
                  onTap: () => context.pushNamed(RouteNames.securitySettings),
                ),
                const _BiometricRow(),
              ],
            ),
            _Group(
              title: context.l10n.settingsCreditSettings,
              rows: [
                _SettingsRow(
                  icon: Icons.alarm_rounded,
                  label: context.l10n.settingsPaymentReminders,
                  onTap: () => context.pushNamed(RouteNames.paymentReminders),
                ),
              ],
            ),
            _Group(
              title: context.l10n.settingsSupportLegal,
              rows: [
                _SettingsRow(
                  icon: Icons.help_outline_rounded,
                  label: context.l10n.settingsHelpCenter,
                  onTap: () => context.pushNamed(RouteNames.support),
                ),
                _SettingsRow(
                  icon: Icons.description_outlined,
                  label: context.l10n.accountTerms,
                  onTap: () => context.pushNamed(RouteNames.terms),
                ),
                _SettingsRow(
                  icon: Icons.privacy_tip_outlined,
                  label: context.l10n.accountPrivacy,
                  onTap: () => context.pushNamed(RouteNames.privacyPolicy),
                ),
                _SettingsRow(
                  icon: Icons.info_outline_rounded,
                  label: context.l10n.accountAboutUs,
                  onTap: () => context.pushNamed(RouteNames.about),
                ),
              ],
            ),
            AppSpacing.vGapSm,
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: AppRadius.brLg,
                border: Border.all(color: vs.border),
              ),
              child: Column(
                children: [
                  _DangerRow(
                    label: context.l10n.accountLogout,
                    onTap: () => _confirm(
                      context,
                      ref,
                      title: context.l10n.settingsLogoutQ,
                      body:
                          'You will need to sign in again to access your account.',
                      confirmLabel: context.l10n.accountLogout,
                      onConfirm: () {
                        ref.read(analyticsServiceProvider).track('logout');
                        ref.read(authControllerProvider.notifier).logout();
                      },
                    ),
                  ),
                  Divider(height: 1, color: vs.border),
                  _DangerRow(
                    label: context.l10n.accountDeleteAccount,
                    onTap: () => _confirm(
                      context,
                      ref,
                      title: context.l10n.settingsDeleteAccountQ,
                      body:
                          'This submits a request to permanently delete your '
                          'account and data. Our team will process it, and you '
                          'will be signed out now.',
                      confirmLabel: context.l10n.commonDelete,
                      onConfirm: () => _requestAccountDeletion(context, ref),
                    ),
                  ),
                ],
              ),
            ),
            AppSpacing.vGapLg,
            Center(
              child: Text('v1.0.0',
                  style: AppTypography.labelSmall
                      .copyWith(color: vs.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }
}

/// A titled section: gray uppercase label + a white card of rows with dividers.
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xs, AppSpacing.md, AppSpacing.xs, AppSpacing.sm),
          child: Text(
            title.toUpperCase(),
            style: AppTypography.labelSmall
                .copyWith(color: vs.textSecondary, letterSpacing: 1),
          ),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: AppRadius.brLg,
            border: Border.all(color: vs.border),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i != 0)
                  Divider(height: 1, indent: 52, color: vs.border),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailingText,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? trailingText;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
        child: Row(
          children: [
            Icon(icon, size: 22, color: context.colors.onSurface),
            AppSpacing.hGapMd,
            Expanded(child: Text(label, style: AppTypography.bodyLarge)),
            if (trailingText != null)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: Text(trailingText!,
                    style: AppTypography.bodySmall
                        .copyWith(color: vs.textSecondary)),
              ),
            Icon(Icons.chevron_right_rounded, size: 20, color: vs.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// Biometric app-lock toggle. Backed by [securityPrefsProvider], which persists
/// the choice to the local settings box — this is a device-local preference (the
/// app authenticates via OTP; there is no server-side password/session model).
///
/// NOTE: MPIN, password change and device-management are intentionally not
/// surfaced here — there is no backend for them yet. They are future work.
class _BiometricRow extends ConsumerWidget {
  const _BiometricRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(securityPrefsProvider).biometric;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(Icons.fingerprint_rounded,
              size: 22, color: context.colors.onSurface),
          AppSpacing.hGapMd,
          Expanded(
              child: Text(context.l10n.settingsBiometricLogin,
                  style: AppTypography.bodyLarge)),
          Switch(
            value: on,
            onChanged: (v) =>
                ref.read(securityPrefsProvider.notifier).setBiometric(v),
          ),
        ],
      ),
    );
  }
}

class _DangerRow extends StatelessWidget {
  const _DangerRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(
          child: Text(
            label,
            style: AppTypography.labelLarge.copyWith(color: AppColors.error),
          ),
        ),
      ),
    );
  }
}
