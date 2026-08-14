import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../features/collections/presentation/collection_detail_screen.dart';
import '../../features/deliveries/presentation/delivery_detail_screen.dart';
import '../../features/verification/presentation/verification_detail_screen.dart';

/// `kind` values (from a push's `data`) meaning "a brand-new task just landed
/// on this agent" — worth a full-screen, vibrating alert instead of a normal
/// tray notification. Must mirror the backend's `URGENT_KINDS`
/// (notifications/push.py) — that's what decides these arrive DATA-ONLY, which
/// is what lets [firebaseMessagingBackgroundHandler] build the alert itself
/// even while the app is backgrounded or fully terminated.
const urgentAssignmentKinds = {'delivery_assignment', 'collection_assignment'};

bool isUrgentAssignment(Map<String, dynamic> data) =>
    urgentAssignmentKinds.contains((data['kind'] ?? '').toString());

const urgentChannelId = 'vsmart_urgent';

// Android's Notification.FLAG_INSISTENT — the platform repeats the
// notification's sound + vibration on a loop until it's cancelled or the
// user acts on it, exactly the "keeps ringing like an incoming call" behavior
// an assignment alert needs. This is an OS-level repeat, so it keeps working
// even if the alert was built by the background isolate and the app process
// is killed right after — there's no Dart timer to lose.
const _flagInsistent = 4;

/// How long the ringing alert keeps sounding before Android clears it by
/// itself. Long enough that a rider who feels it in a pocket can get to the
/// phone; short enough that an unanswered alert doesn't ring forever.
const Duration _ringTimeout = Duration(minutes: 2);

/// The one id an assignment's ringing alert is always shown/cancelled under —
/// stable per task so [IncomingTaskScreen] can silence the exact alert it's
/// answering, from either isolate, without needing to share any other state.
int ringingAlertId(Map<String, dynamic> data) {
  final key = (data['taskId'] as String?)?.trim().isNotEmpty == true
      ? 'd:${data['taskId']}'
      : 'c:${(data['collectionId'] ?? '').toString()}';
  return key.hashCode;
}

/// Shows (or re-shows) the full-screen, insistently-ringing assignment alert.
/// Used identically by the foreground path (push_controller.dart) and the
/// background isolate (push_service.dart) so a brand-new assignment rings the
/// same way regardless of app state — the only difference is which one also
/// navigates to [IncomingTaskScreen] directly instead of waiting for a tap.
Future<void> showRingingAlert(
  FlutterLocalNotificationsPlugin local,
  Map<String, dynamic> data,
) async {
  const channel = AndroidNotificationChannel(
    urgentChannelId,
    'New task alert',
    description: 'A brand-new delivery or collection just came in',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );
  await local
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  final title = (data['title'] ?? 'New task assigned').toString();
  final body = (data['body'] ?? '').toString();

  await local.show(
    ringingAlertId(data),
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: Importance.max,
        priority: Priority.max,
        // Wakes/launches the app over the lock screen, like an incoming call.
        fullScreenIntent: true,
        category: AndroidNotificationCategory.call,
        visibility: NotificationVisibility.public,
        icon: 'ic_notification',
        playSound: true,
        enableVibration: true,
        ongoing: true,
        autoCancel: false,
        additionalFlags: Int32List.fromList(<int>[_flagInsistent]),
        // Stop ringing on its own if nobody ever answers.
        //
        // FLAG_INSISTENT repeats the sound until the notification is
        // cancelled, and `ongoing: true` means it cannot be swiped away. The
        // only thing that cancelled it was `IncomingTaskScreen.dispose()` — so
        // an alert the agent never opened (phone in a pocket, screen dismissed,
        // app killed) rang indefinitely with no way to stop it short of a
        // reboot. A ring nobody answered in two minutes has failed at being a
        // ring; the task still sits in their list either way.
        timeoutAfter: _ringTimeout.inMilliseconds,
      ),
    ),
    payload: encodePushPayload(data),
  );
}

/// Stops the ring — call the moment the agent accepts, rejects, or otherwise
/// leaves [IncomingTaskScreen]. Cancelling the notification is what actually
/// silences FLAG_INSISTENT's repeat. Called fire-and-forget from
/// [IncomingTaskScreen]'s `dispose()` (which can't be `async`), so this
/// fails soft rather than risking an unhandled rejection with no relation to
/// whatever the app does next.
Future<void> cancelRingingAlert(
  FlutterLocalNotificationsPlugin local,
  Map<String, dynamic> data,
) async {
  try {
    await local.cancel(ringingAlertId(data));
  } catch (_) {
    // best-effort — the alert may already be gone (tapped/auto-cleared)
  }
}

/// Notification tap payloads round-trip through flutter_local_notifications as
/// a single string — encode/decode the FCM data map as a query string. Shared
/// by the foreground app (push_controller.dart) and the background isolate
/// (push_service.dart), which must agree on the exact same format.
String encodePushPayload(Map<String, dynamic> data) => data.entries
    .map((e) =>
        '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent('${e.value}')}')
    .join('&');

Map<String, dynamic> decodePushPayload(String payload) {
  final out = <String, dynamic>{};
  for (final pair in payload.split('&')) {
    final i = pair.indexOf('=');
    if (i <= 0) continue;
    out[Uri.decodeComponent(pair.substring(0, i))] =
        Uri.decodeComponent(pair.substring(i + 1));
  }
  return out;
}

/// Resolve a push payload to a shell tab index, or null to leave the tab as-is.
/// Prefers an explicit `route`, then `kind`, then `type`.
int? tabForPush(Map<String, dynamic> data) {
  final route = (data['route'] as String?)?.trim().toLowerCase();
  final kind = (data['kind'] as String?)?.trim().toLowerCase() ?? '';
  final type = (data['type'] as String?)?.trim().toLowerCase() ?? '';
  if (route != null && route.isNotEmpty) {
    if (route.contains('deliver')) return 2;
    if (route.contains('collect')) return 1;
    if (route.contains('verif') || route.contains('task')) return 3;
  }
  if (kind.contains('deliver') || type == 'delivery') return 2;
  if (kind.contains('collect') || type == 'payment' || type == 'credit') {
    return 1;
  }
  if (kind.contains('verif')) return 3;
  return null;
}

/// Builds the specific screen a push payload points at, or null when it
/// carries no task id (e.g. a generic/admin notification with nothing to open
/// beyond the tab itself).
Widget? detailScreenForPush(Map<String, dynamic> data) {
  final deliveryId = (data['taskId'] as String?)?.trim();
  if (deliveryId != null &&
      deliveryId.isNotEmpty &&
      (data['kind'] as String?)?.contains('delivery') == true) {
    return DeliveryDetailScreen(
      id: deliveryId,
      orderCode: (data['orderCode'] as String?)?.trim() ?? '',
    );
  }
  final collectionId = (data['collectionId'] as String?)?.trim();
  if (collectionId != null && collectionId.isNotEmpty) {
    return CollectionDetailScreen(id: collectionId);
  }
  final verificationId = (data['verificationId'] as String?)?.trim();
  if (verificationId != null && verificationId.isNotEmpty) {
    return VerificationDetailScreen(id: verificationId);
  }
  return null;
}
