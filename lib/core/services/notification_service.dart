import 'package:firebase_messaging/firebase_messaging.dart';

import '../utils/app_logger.dart';

/// Top-level background handler. Must be a top-level/static function for FCM.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  AppLogger.i('BG notification: ${message.messageId}');
}

/// Wraps Firebase Cloud Messaging: permissions, token, and message streams.
class NotificationService {
  NotificationService(this._messaging);

  final FirebaseMessaging _messaging;

  factory NotificationService.create() =>
      NotificationService(FirebaseMessaging.instance);

  /// Request notification permission (iOS/Android 13+).
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

  /// Foreground messages.
  Stream<RemoteMessage> get onMessage => FirebaseMessaging.onMessage;

  /// User tapped a notification that opened the app from background.
  Stream<RemoteMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp;

  /// Notification that launched the app from a terminated state.
  Future<RemoteMessage?> getInitialMessage() => _messaging.getInitialMessage();

  Future<void> subscribeToTopic(String topic) =>
      _messaging.subscribeToTopic(topic);

  Future<void> unsubscribeFromTopic(String topic) =>
      _messaging.unsubscribeFromTopic(topic);
}
