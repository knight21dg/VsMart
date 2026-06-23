import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../providers/notification_preferences_provider.dart';

/// Payment Reminders — lets the customer configure how and when VS Mart alerts
/// them about upcoming credit payments. Backed by `/notifications/preferences`
/// (`reminderEnabled`, `reminderOffsetDays`, `reminderTime` and the channel
/// switches), so the choices persist across sessions.
class PaymentRemindersScreen extends ConsumerStatefulWidget {
  const PaymentRemindersScreen({super.key});

  @override
  ConsumerState<PaymentRemindersScreen> createState() =>
      _PaymentRemindersScreenState();
}

/// The reminder-timing options shown in the selectable grid.
enum _ReminderTiming { threeDays, oneDay, onDueDate, custom }

class _PaymentRemindersScreenState
    extends ConsumerState<PaymentRemindersScreen> {
  bool _seeded = false;
  bool _saving = false;

  bool _remindersEnabled = true;
  _ReminderTiming _timing = _ReminderTiming.threeDays;
  bool _whatsApp = true;
  bool _push = true;
  bool _sms = false;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 9, minute: 0);

  void _seed(NotificationPreferences p) {
    _remindersEnabled = p.reminderEnabled;
    _timing = _timingFromDays(p.reminderOffsetDays);
    _whatsApp = p.whatsapp;
    _push = p.push;
    _sms = p.sms;
    _reminderTime = _parseTime(p.reminderTime) ?? const TimeOfDay(hour: 9, minute: 0);
    _seeded = true;
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _reminderTime,
    );
    if (picked != null) setState(() => _reminderTime = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await ref
        .read(notificationPreferencesProvider.notifier)
        .saveReminders(
          enabled: _remindersEnabled,
          offsetDays: _daysFromTiming(_timing),
          time: _timeToString(_reminderTime),
          whatsapp: _whatsApp,
          push: _push,
          sms: _sms,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    context.showSnack(
      ok ? 'Reminder preferences saved.' : 'Could not save preferences.',
      isError: !ok,
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefsAsync = ref.watch(notificationPreferencesProvider);

    return Scaffold(
      appBar: const VSAppBar(title: 'Payment Reminders'),
      body: SafeArea(
        top: false,
        child: prefsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => VSErrorView(
            message: "Couldn't load your reminder preferences.",
            onRetry: () => ref.invalidate(notificationPreferencesProvider),
          ),
          data: (prefs) {
            if (!_seeded) _seed(prefs);
            return _form(context);
          },
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final vs = context.vsColors;
    final disabled = !_remindersEnabled;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      children: [
        Text('Stay on track', style: AppTypography.headlineLarge),
        AppSpacing.vGapXs,
        Text(
          'Configure your alerts to avoid late fees and maintain a healthy '
          'credit score with VS Mart.',
          style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
        ),
        AppSpacing.vGapLg,

        // ----- Master enable -----
        _Card(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              _LeadingIcon(
                icon: Icons.notifications_active_rounded,
                color: vs.brand,
                tint: vs.brandTint,
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Enable Reminders', style: AppTypography.titleMedium),
                    AppSpacing.vGapXs,
                    Text(
                      'Get notified before your due date',
                      style: AppTypography.bodySmall.copyWith(
                        color: vs.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _remindersEnabled,
                onChanged: (v) => setState(() => _remindersEnabled = v),
              ),
            ],
          ),
        ),
        AppSpacing.vGapXl,

        // ----- Timing selection -----
        const _SectionTitle('When should we remind you?'),
        AppSpacing.vGapMd,
        Opacity(
          opacity: disabled ? 0.5 : 1,
          child: IgnorePointer(
            ignoring: disabled,
            child: Row(
              children: [
                Expanded(
                  child: _TimingCard(
                    icon: Icons.event_available_rounded,
                    title: '3 Days Before',
                    subtitle: 'Best for planning ahead',
                    selected: _timing == _ReminderTiming.threeDays,
                    onTap: () =>
                        setState(() => _timing = _ReminderTiming.threeDays),
                  ),
                ),
                AppSpacing.hGapMd,
                Expanded(
                  child: _TimingCard(
                    icon: Icons.timer_outlined,
                    title: '1 Day Before',
                    subtitle: 'Quick reminder',
                    selected: _timing == _ReminderTiming.oneDay,
                    onTap: () =>
                        setState(() => _timing = _ReminderTiming.oneDay),
                  ),
                ),
              ],
            ),
          ),
        ),
        AppSpacing.vGapMd,
        Opacity(
          opacity: disabled ? 0.5 : 1,
          child: IgnorePointer(
            ignoring: disabled,
            child: Row(
              children: [
                Expanded(
                  child: _TimingCard(
                    icon: Icons.event_rounded,
                    title: 'On Due Date',
                    subtitle: 'Morning of payment',
                    selected: _timing == _ReminderTiming.onDueDate,
                    onTap: () =>
                        setState(() => _timing = _ReminderTiming.onDueDate),
                  ),
                ),
                AppSpacing.hGapMd,
                Expanded(
                  child: _TimingCard(
                    icon: Icons.tune_rounded,
                    title: 'A Week Before',
                    subtitle: 'Maximum lead time',
                    selected: _timing == _ReminderTiming.custom,
                    onTap: () =>
                        setState(() => _timing = _ReminderTiming.custom),
                  ),
                ),
              ],
            ),
          ),
        ),
        AppSpacing.vGapXl,

        // ----- Channels -----
        const _SectionTitle('How should we reach you?'),
        AppSpacing.vGapMd,
        Opacity(
          opacity: disabled ? 0.5 : 1,
          child: IgnorePointer(
            ignoring: disabled,
            child: _Card(
              child: Column(
                children: [
                  _ChannelRow(
                    icon: Icons.chat_rounded,
                    iconColor: vs.brand,
                    tint: vs.brandTint,
                    title: 'WhatsApp',
                    subtitle: 'Instant message delivery',
                    value: _whatsApp,
                    onChanged: (v) => setState(() => _whatsApp = v),
                  ),
                  Divider(height: 1, indent: 64, color: vs.border),
                  _ChannelRow(
                    icon: Icons.phone_iphone_rounded,
                    iconColor: vs.trust,
                    tint: vs.trustTint,
                    title: 'Push Notification',
                    subtitle: 'Direct to your VS Mart app',
                    value: _push,
                    onChanged: (v) => setState(() => _push = v),
                  ),
                  Divider(height: 1, indent: 64, color: vs.border),
                  _ChannelRow(
                    icon: Icons.sms_rounded,
                    iconColor: vs.offer,
                    tint: vs.offerTint,
                    title: 'SMS Text',
                    subtitle: 'Standard text message',
                    value: _sms,
                    onChanged: (v) => setState(() => _sms = v),
                  ),
                ],
              ),
            ),
          ),
        ),
        AppSpacing.vGapXl,

        // ----- Preferred time -----
        const _SectionTitle('Preferred Time'),
        AppSpacing.vGapMd,
        Opacity(
          opacity: disabled ? 0.5 : 1,
          child: IgnorePointer(
            ignoring: disabled,
            child: _Card(
              child: InkWell(
                borderRadius: AppRadius.brLg,
                onTap: _pickTime,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    children: [
                      _LeadingIcon(
                        icon: Icons.access_time_rounded,
                        color: vs.brand,
                        tint: vs.brandTint,
                      ),
                      AppSpacing.hGapMd,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Time of day',
                                style: AppTypography.titleMedium),
                            AppSpacing.vGapXs,
                            Text(
                              _reminderTime.format(context),
                              style: AppTypography.bodySmall.copyWith(
                                color: vs.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 22,
                        color: vs.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        AppSpacing.vGapLg,

        // ----- Info banner -----
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: vs.trustTint,
            borderRadius: AppRadius.brLg,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_rounded, size: 20, color: vs.trust),
              AppSpacing.hGapMd,
              Expanded(
                child: Text(
                  'Setting reminders helps you avoid late fees and positively '
                  'impacts your credit health by ensuring timely payments.',
                  style: AppTypography.bodySmall.copyWith(color: vs.trust),
                ),
              ),
            ],
          ),
        ),
        AppSpacing.vGapXl,

        // ----- Save -----
        VSButton(
          label: 'Save Preferences',
          isLoading: _saving,
          onPressed: _save,
        ),
      ],
    );
  }
}

_ReminderTiming _timingFromDays(int d) => switch (d) {
      3 => _ReminderTiming.threeDays,
      1 => _ReminderTiming.oneDay,
      0 => _ReminderTiming.onDueDate,
      _ => _ReminderTiming.custom,
    };

int _daysFromTiming(_ReminderTiming t) => switch (t) {
      _ReminderTiming.threeDays => 3,
      _ReminderTiming.oneDay => 1,
      _ReminderTiming.onDueDate => 0,
      _ReminderTiming.custom => 7,
    };

TimeOfDay? _parseTime(String? s) {
  if (s == null || s.isEmpty) return null;
  final parts = s.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return TimeOfDay(hour: h, minute: m);
}

String _two(int n) => n.toString().padLeft(2, '0');
String _timeToString(TimeOfDay t) => '${_two(t.hour)}:${_two(t.minute)}';

/// Surface card with the standard VS Mart border + radius.
class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: padding,
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
      ),
      child: child,
    );
  }
}

/// Uppercase-style section heading.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: AppTypography.headlineSmall);
  }
}

/// Rounded tinted square holding a leading brand/channel icon.
class _LeadingIcon extends StatelessWidget {
  const _LeadingIcon({
    required this.icon,
    required this.color,
    required this.tint,
  });

  final IconData icon;
  final Color color;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: AppRadius.brMd,
      ),
      child: Icon(icon, size: 22, color: color),
    );
  }
}

/// A selectable reminder-timing option in the 2x2 grid.
class _TimingCard extends StatelessWidget {
  const _TimingCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      borderRadius: AppRadius.brLg,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: selected ? vs.brandTint : context.colors.surface,
          borderRadius: AppRadius.brLg,
          border: Border.all(
            color: selected ? vs.brand : vs.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 22, color: context.colors.onSurface),
                const Spacer(),
                if (selected)
                  Icon(Icons.check_circle_rounded, size: 20, color: vs.brand),
              ],
            ),
            AppSpacing.vGapMd,
            Text(title, style: AppTypography.titleMedium),
            AppSpacing.vGapXs,
            Text(
              subtitle,
              style: AppTypography.bodySmall.copyWith(color: vs.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// A delivery-channel toggle row inside the channels card.
class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.icon,
    required this.iconColor,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final Color tint;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          _LeadingIcon(icon: icon, color: iconColor, tint: tint),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.titleMedium),
                AppSpacing.vGapXs,
                Text(
                  subtitle,
                  style: AppTypography.bodySmall.copyWith(
                    color: vs.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
