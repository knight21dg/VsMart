import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/notifications_data.dart';

final notificationsRepoProvider = Provider<NotificationsRepo>(
  (ref) => NotificationsRepo(ref.watch(apiProvider)),
);

/// The agent's notification inbox, newest first (GET /notifications).
final notificationsProvider =
    FutureProvider.autoDispose<List<AppNotification>>(
  (ref) => ref.watch(notificationsRepoProvider).list(),
);

/// Unread count derived from the inbox — drives the app-bar bell badge.
final unreadNotificationCountProvider = Provider.autoDispose<int>((ref) {
  final async = ref.watch(notificationsProvider);
  return async.maybeWhen(
    data: (items) => items.where((n) => !n.isRead).length,
    orElse: () => 0,
  );
});
