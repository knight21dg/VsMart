import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../notifications/presentation/providers/notification_preferences_provider.dart';

/// Notification Settings — grouped toggle rows (Order, Payment, Credit and
/// Promotional categories plus channel settings). Every toggle persists to
/// `PATCH /notifications/preferences`: channels as top-level fields, per-event
/// categories in the `categories` map.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  // (categoryKey, label, icon, defaultWhenUnset)
  static const List<(String, List<(String, String, IconData, bool)>)> _groups = [
    (
      'Order Notifications',
      [
        ('orderConfirmed', 'Order Confirmed', Icons.check_circle_outline_rounded, true),
        ('orderPacked', 'Order Packed', Icons.inventory_2_outlined, true),
        ('orderOutForDelivery', 'Order Out for Delivery', Icons.local_shipping_outlined, true),
        ('orderDelivered', 'Order Delivered', Icons.task_alt_rounded, true),
      ],
    ),
    (
      'Payment Notifications',
      [
        ('paymentSuccess', 'Payment Success', Icons.payments_outlined, true),
        ('paymentFailure', 'Payment Failure', Icons.error_outline_rounded, false),
        ('paymentReminders', 'Payment Reminders', Icons.alarm_rounded, true),
        ('collectionReminders', 'Collection Reminders', Icons.account_balance_wallet_outlined, true),
      ],
    ),
    (
      'Credit Notifications',
      [
        ('creditApproval', 'Credit Approval', Icons.verified_outlined, true),
        ('creditLimitUpdates', 'Credit Limit Updates', Icons.credit_score_outlined, true),
        ('outstandingDueAlerts', 'Outstanding Due Alerts', Icons.warning_amber_rounded, true),
        ('vsScoreUpdates', 'VS Score Updates', Icons.insights_outlined, false),
      ],
    ),
    (
      'Promotional Notifications',
      [
        ('offers', 'Offers', Icons.local_offer_outlined, true),
        ('coupons', 'Coupons', Icons.confirmation_number_outlined, true),
        ('cashback', 'Cashback', Icons.savings_outlined, true),
        ('referralRewards', 'Referral Rewards', Icons.card_giftcard_rounded, false),
      ],
    ),
  ];

  static const List<(String, String, IconData)> _channels = [
    ('push', 'Push Notifications', Icons.notifications_active_outlined),
    ('sms', 'SMS Notifications', Icons.sms_outlined),
    ('whatsapp', 'WhatsApp Notifications', Icons.chat_bubble_outline_rounded),
    ('email', 'Email Notifications', Icons.mail_outline_rounded),
  ];

  bool _channelValue(NotificationPreferences p, String key) => switch (key) {
        'push' => p.push,
        'sms' => p.sms,
        'whatsapp' => p.whatsapp,
        'email' => p.email,
        _ => false,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(notificationPreferencesProvider);
    final controller = ref.read(notificationPreferencesProvider.notifier);

    return Scaffold(
      appBar: const VSAppBar(title: 'Notification Settings'),
      body: SafeArea(
        top: false,
        child: prefsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => VSErrorView(
            message: "Couldn't load your notification settings.",
            onRetry: () => ref.invalidate(notificationPreferencesProvider),
          ),
          data: (prefs) => ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            children: [
              for (final (title, rows) in _groups)
                _Group(
                  title: title,
                  rows: [
                    for (final (key, label, icon, def) in rows)
                      _ToggleRow(
                        icon: icon,
                        label: label,
                        value: prefs.category(key, fallback: def),
                        onChanged: (v) => controller.setCategory(key, v),
                      ),
                  ],
                ),
              _Group(
                title: 'Channel Settings',
                rows: [
                  for (final (key, label, icon) in _channels)
                    _ToggleRow(
                      icon: icon,
                      label: label,
                      value: _channelValue(prefs, key),
                      onChanged: (v) => controller.setChannel(key, v),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled section: gray uppercase label + a surface card of toggle rows with
/// hairline dividers.
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

/// A single notification toggle: leading icon + label + trailing [Switch].
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: context.colors.onSurface),
          AppSpacing.hGapMd,
          Expanded(child: Text(label, style: AppTypography.bodyLarge)),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
