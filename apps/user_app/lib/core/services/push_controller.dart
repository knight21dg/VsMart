import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/constants/api_constants.dart';
import '../../app/routes/app_router.dart';
import '../../app/theme/app_colors.dart';
import '../../shared/providers/core_providers.dart';
import '../network/api_client.dart';
import '../utils/app_logger.dart';
import 'firebase_service.dart';
import 'notification_route.dart';
import 'notification_service.dart';

/// Orchestrates push end-to-end: registers the device's FCM token with the
/// backend (`POST /notifications/device-token`), shows foreground messages as
/// system notifications (Android doesn't auto-display those), and routes taps
/// via the `data.route` payload. Safe when Firebase isn't configured — every
/// step guards on [FirebaseService.isInitialized] and swallows failures so it
/// can never block app startup or login.
class PushController {
  PushController({
    required ApiClient api,
    required NotificationService Function() notifications,
    required GoRouter Function() router,
  })  : _api = api,
        _notificationsFactory = notifications,
        _router = router;

  final ApiClient _api;

  /// Built lazily, and only once [FirebaseService.isInitialized] is confirmed.
  ///
  /// Taking the instance eagerly used to crash the whole app on a device with
  /// no `google-services.json`: `NotificationService.create()` reaches for
  /// `FirebaseMessaging.instance`, which throws `[core/no-app]` before
  /// [start]'s Firebase guard could ever run. Because this provider is read
  /// from a `ref.listen` on the current user, that exception surfaced *during a
  /// router redirect* right after sign-in and took navigation down with it.
  final NotificationService Function() _notificationsFactory;
  NotificationService? _notifications;

  final GoRouter Function() _router;

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  // Notification channels, mirrored on the backend (notifications/push.py). The
  // server stamps each push with `data.channel` (and `data.type`); we render
  // foreground pushes on the matching channel and create every channel up front
  // so users can tune each category in Android system settings.
  static const AndroidNotificationChannel _orders = AndroidNotificationChannel(
    'vsmart_orders',
    'Orders',
    description: 'Order confirmations, packing and status updates',
    importance: Importance.high,
  );
  static const AndroidNotificationChannel _delivery = AndroidNotificationChannel(
    'vsmart_delivery',
    'Delivery',
    description: 'Rider assignment and live delivery updates',
    importance: Importance.high,
  );
  static const AndroidNotificationChannel _credit = AndroidNotificationChannel(
    'vsmart_credit',
    'Payments & Credit',
    description: 'Payments, VS Credit dues and reminders',
    importance: Importance.high,
  );
  static const AndroidNotificationChannel _offers = AndroidNotificationChannel(
    'vsmart_offers',
    'Offers',
    description: 'Deals, coupons and promotions',
    importance: Importance.defaultImportance,
  );
  static const AndroidNotificationChannel _support = AndroidNotificationChannel(
    'vsmart_support',
    'Account & Support',
    description: 'Account, security and support messages',
    importance: Importance.high,
  );

  static const List<AndroidNotificationChannel> _channels = [
    _orders,
    _delivery,
    _credit,
    _offers,
    _support,
  ];

  // notify(type=...) -> channel id. Mirror of CHANNEL_BY_TYPE in push.py; the
  // server already resolves this into `data.channel`, so this is the fallback
  // for any push that arrives with only a `type`.
  static const Map<String, String> _channelByType = {
    'order': 'vsmart_orders',
    'delivery': 'vsmart_delivery',
    'payment': 'vsmart_credit',
    'credit': 'vsmart_credit',
    'offer': 'vsmart_offers',
    'promo': 'vsmart_offers',
    'admin': 'vsmart_support',
    'support': 'vsmart_support',
  };

  /// Picks the channel for a push from its `data`: prefer the server-resolved
  /// `channel`, fall back to mapping `type`, then to the general channel.
  AndroidNotificationChannel _channelFor(Map<String, dynamic> data) {
    final fromServer = (data['channel'] as String?)?.trim();
    final id = (fromServer != null && fromServer.isNotEmpty)
        ? fromServer
        : _channelByType[(data['type'] as String?)?.trim().toLowerCase()] ??
            _support.id;
    return _channels.firstWhere((c) => c.id == id, orElse: () => _support);
  }

  bool _started = false;

  /// Idempotent. Call once the user is authenticated. Re-callable after a reset
  /// (e.g. on re-login) — [reset] clears the guard.
  Future<void> start() async {
    if (_started || !FirebaseService.isInitialized) return;
    _started = true;
    try {
      // Safe to touch Firebase only now that isInitialized is confirmed.
      final notifications = _notifications ??= _notificationsFactory();

      await notifications.requestPermission();
      await _initLocal();

      // Foreground messages: surface them as a system notification ourselves.
      notifications.onMessage.listen(_showLocal);
      // Tap that opened the app from background.
      notifications.onMessageOpenedApp.listen((m) => _route(m.data));
      // Tap that launched the app from terminated.
      final initial = await notifications.getInitialMessage();
      if (initial != null) _route(initial.data);
      // Token rotation.
      notifications.onTokenRefresh.listen(_registerToken);

      await _registerToken(await notifications.getToken());
    } catch (e, st) {
      AppLogger.w('Push start failed: $e');
      AppLogger.d(st);
      _started = false; // allow a later retry
    }
  }

  /// Clear the started guard so a subsequent [start] re-runs (used on re-login).
  void reset() => _started = false;

  Future<void> _initLocal() async {
    // Branded white silhouette in res/drawable (matches the FCM default icon
    // declared in AndroidManifest for background notifications).
    const android = AndroidInitializationSettings('ic_notification');
    const ios = DarwinInitializationSettings();
    await _local.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        if (payload != null && payload.isNotEmpty) _route(_decode(payload));
      },
    );
    final androidPlugin = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    for (final channel in _channels) {
      await androidPlugin?.createNotificationChannel(channel);
    }
  }

  Future<void> _showLocal(RemoteMessage message) async {
    final n = message.notification;
    if (n == null) return;
    final channel = _channelFor(message.data);
    // Background/terminated notifications get their image drawn by Android
    // itself straight from the FCM payload — nothing to do there. A
    // foreground push is drawn by this app via flutter_local_notifications,
    // which needs the image as bytes (not just a URL), so fetch it first.
    final imageUrl = n.android?.imageUrl ?? message.data['image'] as String?;
    final image = await _downloadImage(imageUrl);
    await _local.show(
      n.hashCode,
      n.title,
      n.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: channel.importance,
          priority: Priority.high,
          icon: 'ic_notification',
          color: AppColors.vsGreen,
          styleInformation: image == null
              ? null
              : BigPictureStyleInformation(
                  image,
                  largeIcon: image,
                  contentTitle: n.title,
                  summaryText: n.body,
                ),
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: _encode(message.data),
    );
  }

  /// Fetches a push notification's image as bytes for
  /// [BigPictureStyleInformation]. Fails soft — a broken/unreachable image
  /// just means a plain notification, never a dropped notification.
  Future<ByteArrayAndroidBitmap?> _downloadImage(String? url) async {
    if (url == null || url.isEmpty) return null;
    try {
      final res = await Dio().get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      final bytes = res.data;
      if (bytes == null || bytes.isEmpty) return null;
      return ByteArrayAndroidBitmap(Uint8List.fromList(bytes));
    } catch (e) {
      AppLogger.w('Notification image download failed: $e');
      return null;
    }
  }

  Future<void> _registerToken(String? token) async {
    if (token == null || token.isEmpty) return;
    try {
      await _api.post(
        ApiConstants.registerDeviceToken,
        data: {'token': token, 'platform': _platform()},
      );
    } catch (e) {
      AppLogger.w('Device token registration failed: $e');
    }
  }

  void _route(Map<String, dynamic> data) {
    // Shared with the in-app notification list so the two can't drift again.
    final route = resolveNotificationPath(data['route']);
    if (route == null) return;
    try {
      _router().go(route);
    } catch (e) {
      AppLogger.w('Push route failed for "$route": $e');
    }
  }

  String _platform() {
    if (kIsWeb) return 'android';
    return Platform.isIOS ? 'ios' : 'android';
  }

  // Notification tap payloads round-trip through the local-notifications plugin
  // as a single string, so encode the FCM data map as a query string.
  String _encode(Map<String, dynamic> data) => data.entries
      .map((e) =>
          '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent('${e.value}')}')
      .join('&');

  Map<String, dynamic> _decode(String payload) {
    final out = <String, dynamic>{};
    for (final pair in payload.split('&')) {
      final i = pair.indexOf('=');
      if (i <= 0) continue;
      out[Uri.decodeComponent(pair.substring(0, i))] =
          Uri.decodeComponent(pair.substring(i + 1));
    }
    return out;
  }
}

/// App-wide push orchestrator. `router` is read lazily so a notification tap
/// always navigates the current router instance.
final pushControllerProvider = Provider<PushController>((ref) {
  return PushController(
    api: ref.watch(apiClientProvider),
    // Read lazily — see PushController._notificationsFactory. Watching this
    // eagerly makes merely *constructing* the controller throw when Firebase
    // isn't configured.
    notifications: () => ref.read(notificationServiceProvider),
    router: () => ref.read(goRouterProvider),
  );
});
