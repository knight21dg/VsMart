import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/app_error_presenter.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../notifications/presentation/providers/notification_preferences_provider.dart';

/// Notification Settings — grouped toggle rows (Order, Payment, Credit and
/// Promotional categories plus channel settings). Every toggle persists to
/// `PATCH /notifications/preferences`: channels as top-level fields, per-event
/// categories in the `categories` map.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  // (groupTitleKey, [(categoryKey, icon, defaultWhenUnset)]). Labels are resolved
  // from the localizations at render time (see _groupTitle / _catLabel) so no
  // English text is embedded in this const list.
  static const List<(String, List<(String, IconData, bool)>)> _groups = [
    (
      'orders',
      [
        ('orderConfirmed', Icons.check_circle_outline_rounded, true),
        ('orderPacked', Icons.inventory_2_outlined, true),
        ('orderOutForDelivery', Icons.local_shipping_outlined, true),
        ('orderDelivered', Icons.task_alt_rounded, true),
      ],
    ),
    (
      'payments',
      [
        ('paymentSuccess', Icons.payments_outlined, true),
        ('paymentFailure', Icons.error_outline_rounded, false),
        ('paymentReminders', Icons.alarm_rounded, true),
        ('collectionReminders', Icons.account_balance_wallet_outlined, true),
      ],
    ),
    (
      'credit',
      [
        ('creditApproval', Icons.verified_outlined, true),
        ('creditLimitUpdates', Icons.credit_score_outlined, true),
        ('outstandingDueAlerts', Icons.warning_amber_rounded, true),
        ('vsScoreUpdates', Icons.insights_outlined, false),
      ],
    ),
    (
      'promotional',
      [
        ('offers', Icons.local_offer_outlined, true),
        ('coupons', Icons.confirmation_number_outlined, true),
        ('cashback', Icons.savings_outlined, true),
        ('referralRewards', Icons.card_giftcard_rounded, false),
      ],
    ),
  ];

  static const List<(String, IconData)> _channels = [
    ('push', Icons.notifications_active_outlined),
    ('sms', Icons.sms_outlined),
    ('whatsapp', Icons.chat_bubble_outline_rounded),
    ('email', Icons.mail_outline_rounded),
  ];

  bool _channelValue(NotificationPreferences p, String key) => switch (key) {
        'push' => p.push,
        'sms' => p.sms,
        'whatsapp' => p.whatsapp,
        'email' => p.email,
        _ => false,
      };

  static String _groupTitle(AppLocalizations l, String key) => switch (key) {
        'orders' => l.notifGroupOrders,
        'payments' => l.notifGroupPayments,
        'credit' => l.notifGroupCredit,
        'promotional' => l.notifGroupPromotional,
        _ => key,
      };

  static String _catLabel(AppLocalizations l, String key) => switch (key) {
        'orderConfirmed' => l.notifOrderConfirmed,
        'orderPacked' => l.notifOrderPacked,
        'orderOutForDelivery' => l.notifOrderOutForDelivery,
        'orderDelivered' => l.notifOrderDelivered,
        'paymentSuccess' => l.notifPaymentSuccess,
        'paymentFailure' => l.notifPaymentFailure,
        'paymentReminders' => l.settingsPaymentReminders,
        'collectionReminders' => l.notifCollectionReminders,
        'creditApproval' => l.notifCreditApproval,
        'creditLimitUpdates' => l.notifCreditLimitUpdates,
        'outstandingDueAlerts' => l.notifOutstandingDueAlerts,
        'vsScoreUpdates' => l.notifVsScoreUpdates,
        'offers' => l.notifOffers,
        'coupons' => l.notifCoupons,
        'cashback' => l.notifCashback,
        'referralRewards' => l.notifReferralRewards,
        _ => key,
      };

  static String _channelLabel(AppLocalizations l, String key) => switch (key) {
        'push' => l.notifPush,
        'sms' => l.notifSms,
        'whatsapp' => l.notifWhatsapp,
        'email' => l.notifEmail,
        _ => key,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(notificationPreferencesProvider);
    final controller = ref.read(notificationPreferencesProvider.notifier);
    final l10n = context.l10n;

    // A failed toggle PATCH rolls the optimistic state back in the provider;
    // surface it to the user through the actionable presenter.
    ref.listen<Failure?>(lastNotificationPrefsFailureProvider, (_, next) {
      if (next != null) {
        presentFailure(context, ref, next);
        ref.read(lastNotificationPrefsFailureProvider.notifier).state = null;
      }
    });

    return Scaffold(
      appBar: VSAppBar(title: l10n.settingsNotifications),
      body: SafeArea(
        top: false,
        child: prefsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => VSErrorView(
            message: l10n.notifLoadError,
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
              for (final (groupKey, rows) in _groups)
                _Group(
                  title: _groupTitle(l10n, groupKey),
                  rows: [
                    for (final (key, icon, def) in rows)
                      _ToggleRow(
                        icon: icon,
                        label: _catLabel(l10n, key),
                        value: prefs.category(key, fallback: def),
                        onChanged: (v) => controller.setCategory(key, v),
                      ),
                  ],
                ),
              _Group(
                title: l10n.settingsChannelSettings,
                rows: [
                  for (final (key, icon) in _channels)
                    _ToggleRow(
                      icon: icon,
                      label: _channelLabel(l10n, key),
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
