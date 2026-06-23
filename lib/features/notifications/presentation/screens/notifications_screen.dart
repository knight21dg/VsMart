import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/datetime_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/app_notification.dart';
import '../providers/notification_providers.dart';

enum _Filter { all, orders, credit, payments, offers }

/// Notifications Center — filter tabs, Today/Yesterday/This Week groups, and
/// rich cards (colored icon, importance badge, unread accent, inline CTA)
/// matching the design.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  _Filter _filter = _Filter.all;

  bool _matches(AppNotification n) => switch (_filter) {
        _Filter.all => true,
        _Filter.orders =>
          n.type == NotificationType.order || n.type == NotificationType.delivery,
        _Filter.credit =>
          n.type == NotificationType.credit || n.type == NotificationType.account,
        _Filter.payments => n.type == NotificationType.payment,
        _Filter.offers => n.type == NotificationType.offer,
      };

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final all = ref.watch(notificationsProvider);
    final items = all.where(_matches).toList();
    final hasUnread = all.any((n) => !n.read);

    final today = items.where((n) => n.time.isToday).toList();
    final yesterday = items.where((n) => n.time.isYesterday).toList();
    final earlier = items
        .where((n) => !n.time.isToday && !n.time.isYesterday)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Notifications', style: AppTypography.headlineSmall),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: () =>
                  ref.read(notificationsProvider.notifier).markAllRead(),
              child: Text('Mark all\nread',
                  textAlign: TextAlign.center,
                  style:
                      AppTypography.labelSmall.copyWith(color: vs.trust)),
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.pushNamed(RouteNames.settings),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: _FilterTabs(
            filter: _filter,
            onChanged: (f) => setState(() => _filter = f),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: items.isEmpty
            ? const VSEmptyState(
                title: 'No notifications',
                message: "You're all caught up.",
                icon: Icons.notifications_none_rounded,
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
                children: [
                  if (today.isNotEmpty)
                    _Group(label: 'Today', items: today, onOpen: _open),
                  if (yesterday.isNotEmpty)
                    _Group(
                        label: 'Yesterday',
                        items: yesterday,
                        onOpen: _open),
                  if (earlier.isNotEmpty)
                    _Group(
                        label: 'This Week', items: earlier, onOpen: _open),
                ],
              ),
      ),
    );
  }

  void _open(AppNotification n) {
    ref.read(notificationsProvider.notifier).markRead(n.id);
    final route = n.route;
    if (route == null) return;
    if (route == RouteNames.creditDashboard) {
      context.goNamed(route);
    } else {
      context.pushNamed(route);
    }
  }
}

class _FilterTabs extends StatelessWidget {
  const _FilterTabs({required this.filter, required this.onChanged});

  final _Filter filter;
  final ValueChanged<_Filter> onChanged;

  @override
  Widget build(BuildContext context) {
    const tabs = <(_Filter, String)>[
      (_Filter.all, 'All'),
      (_Filter.orders, 'Orders'),
      (_Filter.credit, 'Credit'),
      (_Filter.payments, 'Payments'),
      (_Filter.offers, 'Offers'),
    ];
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
        children: [
          for (final (value, label) in tabs)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: _Tab(
                label: label,
                selected: filter == value,
                onTap: () => onChanged(value),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final fg = selected ? AppColors.white : context.colors.onSurface;
    return Center(
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.brPill,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: selected ? vs.brand : context.colors.surface,
            borderRadius: AppRadius.brPill,
            border: Border.all(color: selected ? vs.brand : vs.border),
          ),
          child: Text(label,
              style: AppTypography.labelMedium.copyWith(color: fg)),
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(
      {required this.label, required this.items, required this.onOpen});

  final String label;
  final List<AppNotification> items;
  final ValueChanged<AppNotification> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Text(label, style: AppTypography.headlineSmall),
        ),
        for (final n in items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: _NotificationCard(
                notification: n, onTap: () => onOpen(n)),
          ),
      ],
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  ({IconData icon, Color color}) _style(BuildContext context) {
    final vs = context.vsColors;
    return switch (notification.type) {
      NotificationType.order =>
        (icon: Icons.shopping_bag_rounded, color: vs.brand),
      NotificationType.delivery =>
        (icon: Icons.local_shipping_rounded, color: vs.trust),
      NotificationType.credit =>
        (icon: Icons.credit_card_rounded, color: vs.offer),
      NotificationType.payment =>
        (icon: Icons.check_circle_rounded, color: vs.success),
      NotificationType.offer =>
        (icon: Icons.card_giftcard_rounded, color: vs.offer),
      NotificationType.account =>
        (icon: Icons.verified_user_rounded, color: vs.trust),
    };
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final s = _style(context);
    final unread = !notification.read;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: unread ? AppColors.transparent : vs.border),
        boxShadow: unread ? AppShadows.xs : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (unread)
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: s.color,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppRadius.lg),
                  bottomLeft: Radius.circular(AppRadius.lg),
                ),
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: s.color.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(s.icon, size: 20, color: s.color),
                  ),
                  AppSpacing.hGapMd,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(notification.title,
                                  style: AppTypography.titleMedium),
                            ),
                            if (notification.important) ...[
                              AppSpacing.hGapSm,
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.sm, vertical: 2),
                                decoration: BoxDecoration(
                                  color: vs.dangerTint,
                                  borderRadius: AppRadius.brXs,
                                ),
                                child: Text('IMPORTANT',
                                    style: AppTypography.labelSmall
                                        .copyWith(color: vs.danger)),
                              ),
                            ] else if (unread)
                              Container(
                                width: 8,
                                height: 8,
                                margin:
                                    const EdgeInsets.only(left: AppSpacing.sm),
                                decoration: BoxDecoration(
                                  color: vs.trust,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(notification.body,
                            style: AppTypography.bodySmall
                                .copyWith(color: vs.textSecondary)),
                        AppSpacing.vGapXs,
                        Text(notification.time.asRelative,
                            style: AppTypography.labelSmall
                                .copyWith(color: vs.textSecondary)),
                        if (notification.actionLabel != null) ...[
                          AppSpacing.vGapMd,
                          _ActionButton(
                            label: notification.actionLabel!,
                            type: notification.type,
                            onTap: onTap,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton(
      {required this.label, required this.type, required this.onTap});

  final String label;
  final NotificationType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    // Offers use an outlined CTA; delivery/order green; credit/payment blue.
    final outlined = type == NotificationType.offer;
    final fill = switch (type) {
      NotificationType.credit || NotificationType.payment => vs.trust,
      _ => vs.brand,
    };
    if (outlined) {
      return OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: context.colors.onSurface,
          side: BorderSide(color: vs.border),
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
        ),
        child: Text(label, style: AppTypography.labelMedium),
      );
    }
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: fill,
        foregroundColor: AppColors.white,
        elevation: 0,
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
      ),
      child: Text(label,
          style: AppTypography.labelMedium.copyWith(color: AppColors.white)),
    );
  }
}
