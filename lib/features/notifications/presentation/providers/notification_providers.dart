import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../domain/entities/app_notification.dart';

/// In-app notification inbox, backed by `/api/v1/notifications`. Loads on build
/// and tracks read-state through the backend (optimistic UI).
class NotificationsController extends Notifier<List<AppNotification>> {
  ApiClient get _api => ref.read(apiClientProvider);

  @override
  List<AppNotification> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    try {
      final res = await _api.get<dynamic>(ApiConstants.notifications);
      final data = (res.data is Map ? res.data['data'] : res.data) as List? ?? const [];
      state = data.whereType<Map>().map((e) => _toNotification(Map<String, dynamic>.from(e))).toList();
    } catch (_) {/* offline → empty inbox */}
  }

  Future<void> markAllRead() async {
    state = [for (final n in state) n.copyWith(read: true)];
    try {
      await _api.post<dynamic>('${ApiConstants.notifications}/read-all');
    } catch (_) {}
  }

  Future<void> markRead(String id) async {
    state = [for (final n in state) n.id == id ? n.copyWith(read: true) : n];
    try {
      await _api.post<dynamic>(ApiConstants.notificationRead(id));
    } catch (_) {}
  }

  void clear() => state = const [];

  AppNotification _toNotification(Map<String, dynamic> j) {
    final data = (j['data'] as Map?) ?? const {};
    return AppNotification(
      id: (j['id'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      body: (j['body'] ?? '').toString(),
      type: _type(j['type']?.toString()),
      time: DateTime.tryParse(j['createdAt']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      read: j['isRead'] as bool? ?? false,
      important: data['important'] as bool? ?? false,
      actionLabel: data['actionLabel'] as String?,
      route: data['route'] as String?,
    );
  }

  NotificationType _type(String? t) => switch (t) {
        'order' => NotificationType.order,
        'delivery' => NotificationType.delivery,
        'credit' => NotificationType.credit,
        'payment' => NotificationType.payment,
        'offer' => NotificationType.offer,
        _ => NotificationType.account,
      };
}

final notificationsProvider =
    NotifierProvider<NotificationsController, List<AppNotification>>(
        NotificationsController.new);

/// Count of unread notifications, for badges.
final unreadNotificationsProvider = Provider<int>(
  (ref) => ref.watch(notificationsProvider).where((n) => !n.read).length,
);
