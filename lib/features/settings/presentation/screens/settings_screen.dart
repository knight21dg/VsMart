import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../../shared/providers/settings_provider.dart';
import '../../../address/presentation/providers/address_providers.dart';
import '../../../auth/presentation/providers/auth_provider.dart';

/// App settings — matches the design: grouped plain-icon rows for account, app
/// preferences, security, credit and legal, plus a logout / delete-account card.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  String _themeLabel(ThemeMode m) => switch (m) {
        ThemeMode.system => 'System',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
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
              child: Text('Theme', style: AppTypography.titleLarge),
            ),
            for (final m in ThemeMode.values)
              RadioListTile<ThemeMode>(
                value: m,
                groupValue: current,
                activeColor: AppColors.vsGreen,
                title: Text(_themeLabel(m)),
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
            child: const Text('Cancel'),
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

    Future<void> addEmergencyContact() async {
      final controller = TextEditingController();
      final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Emergency Contact'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.phone,
            autofocus: true,
            decoration: const InputDecoration(
                hintText: 'Contact mobile number', prefixText: '+91 '),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(controller.text.trim().length >= 10),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (saved == true && context.mounted) {
        context.showSnack('Emergency contact saved.');
      }
    }

    return Scaffold(
      appBar: const VSAppBar(title: 'Settings'),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
          children: [
            _Group(
              title: 'Account Settings',
              rows: [
                _SettingsRow(
                  icon: Icons.person_outline_rounded,
                  label: 'Edit Profile',
                  onTap: () => context.pushNamed(RouteNames.profile),
                ),
                _SettingsRow(
                  icon: Icons.location_on_outlined,
                  label: 'Manage Addresses',
                  onTap: () => context.pushNamed(RouteNames.addresses),
                ),
                _SettingsRow(
                  icon: Icons.verified_user_outlined,
                  label: 'KYC Details',
                  onTap: () => context.pushNamed(RouteNames.kycDetails),
                ),
                _SettingsRow(
                  icon: Icons.people_outline_rounded,
                  label: 'Family Information',
                  onTap: () => context.pushNamed(RouteNames.familyInfo),
                ),
                _SettingsRow(
                  icon: Icons.contact_phone_outlined,
                  label: 'Emergency Contacts',
                  onTap: addEmergencyContact,
                ),
              ],
            ),
            _Group(
              title: 'App Preferences',
              rows: [
                _SettingsRow(
                  icon: Icons.language_rounded,
                  label: 'Language',
                  trailingText: 'English',
                  onTap: () => context.pushNamed(RouteNames.language),
                ),
                _SettingsRow(
                  icon: Icons.wb_sunny_outlined,
                  label: 'Theme',
                  trailingText: _themeLabel(themeMode),
                  onTap: () => _pickTheme(context, ref),
                ),
                _SettingsRow(
                  icon: Icons.notifications_none_rounded,
                  label: 'Notification Preferences',
                  onTap: () => context.pushNamed(RouteNames.notificationSettings),
                ),
                _SettingsRow(
                  icon: Icons.my_location_rounded,
                  label: 'Location Permissions',
                  onTap: detectLocation,
                ),
              ],
            ),
            _Group(
              title: 'Security Settings',
              rows: [
                _SettingsRow(
                  icon: Icons.dialpad_rounded,
                  label: 'Change MPIN',
                  onTap: () => context.pushNamed(RouteNames.securitySettings),
                ),
                _SettingsRow(
                  icon: Icons.password_rounded,
                  label: 'Change Password',
                  onTap: () => context.pushNamed(RouteNames.securitySettings),
                ),
                _SettingsRow(
                  icon: Icons.devices_other_rounded,
                  label: 'Manage Devices',
                  onTap: () => context.pushNamed(RouteNames.securitySettings),
                ),
                _SettingsRow(
                  icon: Icons.history_rounded,
                  label: 'Login Activity',
                  onTap: () => context.pushNamed(RouteNames.securitySettings),
                ),
                const _BiometricRow(),
              ],
            ),
            _Group(
              title: 'Credit Settings',
              rows: [
                _SettingsRow(
                  icon: Icons.credit_card_rounded,
                  label: 'Credit Notifications',
                  onTap: () => context.pushNamed(RouteNames.notificationSettings),
                ),
                _SettingsRow(
                  icon: Icons.alarm_rounded,
                  label: 'Payment Reminders',
                  onTap: () => context.pushNamed(RouteNames.paymentReminders),
                ),
                _SettingsRow(
                  icon: Icons.event_busy_rounded,
                  label: 'Due Date Alerts',
                  onTap: () => context.pushNamed(RouteNames.paymentReminders),
                ),
                _SettingsRow(
                  icon: Icons.receipt_long_rounded,
                  label: 'Statement Notifications',
                  onTap: () => context.pushNamed(RouteNames.notificationSettings),
                ),
              ],
            ),
            _Group(
              title: 'Support & Legal',
              rows: [
                _SettingsRow(
                  icon: Icons.help_outline_rounded,
                  label: 'Help Center',
                  onTap: () => context.pushNamed(RouteNames.support),
                ),
                _SettingsRow(
                  icon: Icons.description_outlined,
                  label: 'Terms & Conditions',
                  onTap: () => context.pushNamed(RouteNames.terms),
                ),
                _SettingsRow(
                  icon: Icons.privacy_tip_outlined,
                  label: 'Privacy Policy',
                  onTap: () => context.pushNamed(RouteNames.privacyPolicy),
                ),
                _SettingsRow(
                  icon: Icons.info_outline_rounded,
                  label: 'About VS Mart',
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
                    label: 'Logout',
                    onTap: () => _confirm(
                      context,
                      ref,
                      title: 'Log out?',
                      body:
                          'You will need to sign in again to access your account.',
                      confirmLabel: 'Log Out',
                      onConfirm: () {
                        ref.read(analyticsServiceProvider).track('logout');
                        ref.read(authControllerProvider.notifier).logout();
                      },
                    ),
                  ),
                  Divider(height: 1, color: vs.border),
                  _DangerRow(
                    label: 'Delete Account',
                    onTap: () => _confirm(
                      context,
                      ref,
                      title: 'Delete account?',
                      body:
                          'This permanently removes your account and data. This '
                          'cannot be undone.',
                      confirmLabel: 'Delete',
                      onConfirm: () {
                        context.showSnack('Account deleted. Signing you out…');
                        ref.read(authControllerProvider.notifier).logout();
                      },
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

/// Biometric login toggle row (local state — no biometric backend wired yet).
class _BiometricRow extends StatefulWidget {
  const _BiometricRow();

  @override
  State<_BiometricRow> createState() => _BiometricRowState();
}

class _BiometricRowState extends State<_BiometricRow> {
  bool _on = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(Icons.fingerprint_rounded,
              size: 22, color: context.colors.onSurface),
          AppSpacing.hGapMd,
          Expanded(
              child: Text('Biometric Login', style: AppTypography.bodyLarge)),
          Switch(value: _on, onChanged: (v) => setState(() => _on = v)),
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
