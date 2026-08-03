import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui.dart';
import '../../collections/presentation/collection_detail_screen.dart';
import '../../deliveries/presentation/delivery_detail_screen.dart';
import '../data/notifications_data.dart';
import 'notifications_providers.dart';

/// Notifications inbox: newest first, unread highlighted; tap → mark read;
/// a "Mark all read" app-bar action.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _busy = false;
  final _marking = <String>{}; // ids with an in-flight mark-read (dedupe taps)

  NotificationsRepo get _repo => ref.read(notificationsRepoProvider);

  Future<void> _refresh() async {
    ref.invalidate(notificationsProvider);
    await ref.read(notificationsProvider.future).then((_) {}, onError: (_) {});
  }

  Future<void> _markRead(AppNotification n) async {
    if (n.isRead || _marking.contains(n.id)) return;
    _marking.add(n.id);
    try {
      await _repo.markRead(n.id);
      ref.invalidate(notificationsProvider);
    } catch (e) {
      if (mounted) showApiError(context, e, fallback: 'Could not mark as read.');
    } finally {
      _marking.remove(n.id);
    }
  }

  /// Mark read, then deep-link to the related entity when the payload carries a
  /// known target (delivery task / collection). Types without a detail screen
  /// just mark read.
  Future<void> _onTap(AppNotification n) async {
    await _markRead(n);
    if (!mounted) return;
    final dest = _routeFor(n);
    if (dest != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => dest));
    }
  }

  Widget? _routeFor(AppNotification n) {
    final kind = (n.data['kind'] ?? '').toString();
    if (kind == 'delivery_assignment' || n.type == 'delivery') {
      final taskId = (n.data['taskId'] ?? '').toString();
      if (taskId.isNotEmpty) {
        return DeliveryDetailScreen(
            id: taskId, orderCode: (n.data['orderCode'] ?? '').toString());
      }
    }
    if (kind == 'collection_assignment' || n.type == 'payment') {
      final id = (n.data['collectionId'] ?? '').toString();
      if (id.isNotEmpty) return CollectionDetailScreen(id: id);
    }
    return null;
  }

  Future<void> _markAllRead() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _repo.markAllRead();
      ref.invalidate(notificationsProvider);
      if (mounted) showToast(context, 'All notifications marked read');
    } catch (e) {
      if (mounted) showApiError(context, e, fallback: 'Could not mark all as read.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadNotificationCountProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: _busy ? null : _markAllRead,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Mark all read'),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Loading(),
        error: (_, __) => ErrorRetry(
          message: 'Could not load notifications.',
          onRetry: () => ref.invalidate(notificationsProvider),
        ),
        data: (items) {
          if (items.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  EmptyState(
                    icon: Icons.notifications_off_outlined,
                    title: 'No notifications',
                    message: "You're all caught up.",
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _NotificationCard(
                notification: items[i],
                onTap: () => _onTap(items[i]),
              ),
            ),
          );
        },
      ),
    );
  }
}

IconData _notifIcon(AppNotification n) {
  final k = '${n.type} ${n.data['kind'] ?? ''}'.toLowerCase();
  if (k.contains('deliver')) return Icons.local_shipping_rounded;
  if (k.contains('collect') || k.contains('payment')) {
    return Icons.account_balance_wallet_rounded;
  }
  if (k.contains('verif') || k.contains('kyc')) return Icons.verified_user_rounded;
  return Icons.notifications_rounded;
}

Color _notifColor(AppNotification n) {
  final k = '${n.type} ${n.data['kind'] ?? ''}'.toLowerCase();
  if (k.contains('deliver')) return AgentColors.blue;
  if (k.contains('collect') || k.contains('payment')) return AgentColors.brand;
  if (k.contains('verif') || k.contains('kyc')) return AgentColors.pink;
  return AgentColors.amber;
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final unread = !n.isRead;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: unread
              ? AgentColors.brand.withValues(alpha: 0.06)
              : AgentColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: unread ? AgentColors.brand.withValues(alpha: 0.35)
                          : AgentColors.border,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LeadingIcon(icon: _notifIcon(n), color: _notifColor(n)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          n.title.isNotEmpty ? n.title : 'Notification',
                          style: TextStyle(
                            fontWeight:
                                unread ? FontWeight.w800 : FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      if (n.createdAt.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          _relative(n.createdAt),
                          style: const TextStyle(
                            color: AgentColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (n.body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      n.body,
                      style: const TextStyle(
                        color: AgentColors.textSecondary,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _relative(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    final diff = DateTime.now().difference(d.toLocal());
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    final local = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }
}
