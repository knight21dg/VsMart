import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'push_routing.dart';

/// Top-level background handler. Must be a top-level/static function annotated
/// with `@pragma('vm:entry-point')` for FCM to invoke it in a background isolate.
///
/// Android renders ordinary background/terminated notifications from the FCM
/// message itself, so there's usually nothing to draw here. A brand-new task
/// assignment is the one exception: those arrive DATA-ONLY (see the backend's
/// `URGENT_KINDS` in notifications/push.py) specifically so this handler is
/// the one building the alert, as a full-screen, high-importance local
/// notification instead of a normal tray entry — an isolate with no app UI
/// alive still has to be able to do this on its own.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kDebugMode) debugPrint('BG notification: ${message.messageId}');
  if (!isUrgentAssignment(message.data)) return;
  try {
    final local = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('ic_notification');
    await local.initialize(const InitializationSettings(android: androidInit));
    await showRingingAlert(local, message.data);
  } catch (e) {
    if (kDebugMode) debugPrint('Urgent alert failed: $e');
  }
}

/// Thin wrapper over Firebase Cloud Messaging: permission, token, and the
/// foreground / tap message streams the [PushController] listens to.
class PushService {
  PushService(this._messaging);

  final FirebaseMessaging _messaging;

  factory PushService.create() => PushService(FirebaseMessaging.instance);

  /// Request notification permission (Android 13+ / iOS).
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  Future<String?> getToken() => _messaging.getToken();

  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  /// Foreground messages (app open + focused).
  Stream<RemoteMessage> get onMessage => FirebaseMessaging.onMessage;

  /// User tapped a notification that opened the app from the background.
  Stream<RemoteMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp;

  /// Notification that launched the app from a terminated state.
  Future<RemoteMessage?> getInitialMessage() => _messaging.getInitialMessage();
}
