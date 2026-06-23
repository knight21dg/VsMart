import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/settings_provider.dart';

/// Security Settings.
///
/// VS Mart authenticates with phone + OTP, so there is no server-side password
/// or session model to expose. This screen surfaces only the real, device-local
/// security preferences (biometric app-lock + login/security alert opt-ins),
/// persisted via [securityPrefsProvider] — no fabricated device or login lists.
class SecuritySettingsScreen extends ConsumerWidget {
  const SecuritySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(securityPrefsProvider);
    final controller = ref.read(securityPrefsProvider.notifier);
    final vs = context.vsColors;

    return Scaffold(
      appBar: const VSAppBar(title: 'Security Settings'),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          children: [
            _Group(
              title: 'App Lock',
              rows: [
                _ToggleRow(
                  icon: Icons.fingerprint_rounded,
                  label: 'Biometric Lock',
                  subtitle: 'Require fingerprint / Face ID to open VS Mart',
                  value: prefs.biometric,
                  onChanged: controller.setBiometric,
                ),
              ],
            ),
            _Group(
              title: 'Security Alerts',
              rows: [
                _ToggleRow(
                  icon: Icons.login_rounded,
                  label: 'Notify on New Login',
                  subtitle: 'Get notified when your account signs in',
                  value: prefs.notifyNewLogin,
                  onChanged: controller.setNotifyNewLogin,
                ),
                _ToggleRow(
                  icon: Icons.lock_reset_rounded,
                  label: 'Notify on Profile Changes',
                  subtitle: 'Alert me when account details change',
                  value: prefs.notifyPasswordChange,
                  onChanged: controller.setNotifyPasswordChange,
                ),
              ],
            ),
            AppSpacing.vGapLg,
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: vs.trustTint,
                borderRadius: AppRadius.brMd,
              ),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, color: vs.trust, size: 20),
                  AppSpacing.hGapMd,
                  Expanded(
                    child: Text(
                      'Your VS Mart account is secured with one-time password '
                      '(OTP) login on every sign-in.',
                      style: AppTypography.bodySmall
                          .copyWith(color: vs.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A titled section: gray uppercase label + a surface card of rows w/ dividers.
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
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.sm,
          ),
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
                if (i != 0) Divider(height: 1, indent: 52, color: vs.border),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Toggle row: leading icon, label + optional subtitle, trailing [Switch].
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: context.colors.onSurface),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTypography.bodyLarge),
                if (subtitle != null) ...[
                  AppSpacing.vGapXs,
                  Text(
                    subtitle!,
                    style: AppTypography.bodySmall
                        .copyWith(color: vs.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
