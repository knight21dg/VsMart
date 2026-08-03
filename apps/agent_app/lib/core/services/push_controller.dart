import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/notifications/presentation/notifications_providers.dart';
import '../../features/tasks/presentation/incoming_task_screen.dart';
import '../api.dart';
import '../navigation.dart';
import '../providers.dart';
import '../ui.dart';
import 'firebase_service.dart';
import 'push_routing.dart';
import 'push_service.dart';
import 'task_sync.dart';

/// Orchestrates push end-to-end for the agent app: registers the device's FCM
/// token with the backend (`POST /notifications/device-token`), shows foreground
/// messages as system notifications (Android doesn't auto-display those), keeps
/// the in-app inbox badge live, and deep-links a tap to the right shell tab.
///
/// A brand-new task assignment (`kind` = delivery_assignment /
/// collection_assignment) skips the normal notification path entirely and
/// opens [IncomingTaskScreen] instead — full-screen, foreground or not (see
/// push_service.dart for the background/terminated half of this).
///
/// Safe when Firebase isn't configured — every step guards on
/// [FirebaseService.isInitialized] and swallows failures, so it can never block
/// startup or login. This mirrors the customer app's PushController, adapted to
/// the agent app's tab-based navigation (there is no go_router here).
class PushController {
  PushController(this._ref);

  final Ref _ref;

  Api get _api => _ref.read(apiProvider);

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  // Notification channels. IDs MUST match the channel_id the backend bakes into
  // each FCM message (notifications/push.py CHANNEL_BY_TYPE), so background and
  // foreground notifications land on the same channel. Names/descriptions are
  // written for a field agent's mental model ("Collections", not "Payments").
  static const AndroidNotificationChannel _delivery = AndroidNotificationChannel(
    'vsmart_delivery',
    'Deliveries',
    description: 'New delivery assignments and route updates',
    importance: Importance.high,
  );
  static const AndroidNotificationChannel _credit = AndroidNotificationChannel(
    'vsmart_credit',
    'Collections & Payments',
    description: 'New collection assignments and payment confirmations',
    importance: Importance.high,
  );
  static const AndroidNotificationChannel _support = AndroidNotificationChannel(
    'vsmart_support',
    'General',
    description: 'Account, verification tasks and other updates',
    importance: Importance.high,
  );
  // Registered here too (idempotent) even though push_service.dart's
  // background isolate is the one that normally creates it first — a device
  // that's never received a backgrounded urgent alert shouldn't be missing
  // the channel the first time one fires while the app happens to be open.
  static const AndroidNotificationChannel _urgent = AndroidNotificationChannel(
    urgentChannelId,
    'New task alert',
    description: 'A brand-new delivery or collection just came in',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static const List<AndroidNotificationChannel> _channels = [
    _delivery,
    _credit,
    _support,
    _urgent,
  ];

  // notify(type=...) -> channel id. Mirror of CHANNEL_BY_TYPE in push.py; used
  // as a fallback for any foreground push that arrives with only a `type`.
  static const Map<String, String> _channelByType = {
    'delivery': 'vsmart_delivery',
    'payment': 'vsmart_credit',
    'credit': 'vsmart_credit',
    'order': 'vsmart_delivery',
    'admin': 'vsmart_support',
    'support': 'vsmart_support',
  };

  /// Picks the channel for a foreground push from its `data`: prefer the
  /// server-resolved `channel`, fall back to mapping `type`, then to general.
  AndroidNotificationChannel _channelFor(Map<String, dynamic> data) {
    final fromServer = (data['channel'] as String?)?.trim();
    final id = (fromServer != null && fromServer.isNotEmpty)
        ? fromServer
        : _channelByType[(data['type'] as String?)?.trim().toLowerCase()] ??
            _support.id;
    return _channels.firstWhere((c) => c.id == id, orElse: () => _support);
  }

  PushService get _push => _ref.read(pushServiceProvider);

  bool _started = false;

  /// Idempotent. Call once the agent is authenticated. Re-callable after a
  /// [reset] (e.g. on re-login) — [reset] clears the guard.
  Future<void> start() async {
    if (_started || !FirebaseService.isInitialized) return;
    _started = true;
    try {
      await _push.requestPermission();
      await _initLocal();

      // Foreground messages: surface as a system notification + refresh badge.
      _push.onMessage.listen(_onForeground);
      // Tap that opened the app from background.
      _push.onMessageOpenedApp.listen((m) => _handleTap(m.data));
      // Tap that launched the app from terminated.
      final initial = await _push.getInitialMessage();
      if (initial != null) _handleTap(initial.data);
      // Cold launch via the LOCAL notification this app built itself (the
      // urgent full-screen alert, built outside Firebase's own APIs) — the
      // Firebase getInitialMessage() above only ever sees Firebase-drawn
      // notifications, never one push_service.dart built by hand.
      final launchDetails = await _local.getNotificationAppLaunchDetails();
      final launchPayload = launchDetails?.notificationResponse?.payload;
      if (launchDetails?.didNotificationLaunchApp == true &&
          launchPayload != null &&
          launchPayload.isNotEmpty) {
        _handleTap(decodePushPayload(launchPayload));
      }
      // Token rotation.
      _push.onTokenRefresh.listen(_registerToken);

      await _registerToken(await _push.getToken());
    } catch (e) {
      if (kDebugMode) debugPrint('Push start failed: $e');
      _started = false; // allow a later retry
    }
  }

  /// Clear the started guard so a subsequent [start] re-runs (used on re-login).
  void reset() => _started = false;

  Future<void> _initLocal() async {
    const android = AndroidInitializationSettings('ic_notification');
    const ios = DarwinInitializationSettings();
    await _local.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        if (payload != null && payload.isNotEmpty) {
          _handleTap(decodePushPayload(payload));
        }
      },
    );
    final androidPlugin = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    for (final channel in _channels) {
      await androidPlugin?.createNotificationChannel(channel);
    }
  }

  Future<void> _onForeground(RemoteMessage message) async {
    _refreshInbox();
    // A brand-new assignment always opens the full-screen alert directly —
    // building a tray notification for it while the app is already the thing
    // on screen would just be a worse version of the same interruption. The
    // ringing alert is still shown (not skipped) — [IncomingTaskScreen] is
    // what silences it, so foreground and background behave identically:
    // the ring keeps going until the agent actually answers.
    if (isUrgentAssignment(message.data)) {
      await showRingingAlert(_local, message.data);
      _openIncomingTask(message.data);
      return;
    }
    final n = message.notification;
    if (n == null) return;
    final channel = _channelFor(message.data);
    // Background/terminated notifications get their image drawn by Android
    // itself straight from the FCM payload — nothing to do there. A
    // foreground push is drawn by this app via flutter_local_notifications,
    // which needs the image as bytes (not just a URL), so fetch it before
    // showing the notification.
    final imageUrl = n.android?.imageUrl ?? message.data['image'] as String?;
    final image = await _downloadImage(imageUrl);
    _local.show(
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
          color: AgentColors.brand,
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
      payload: encodePushPayload(message.data),
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
      if (kDebugMode) debugPrint('Notification image download failed: $e');
      return null;
    }
  }

  /// Route a tap to the matching shell tab AND, when the payload carries a
  /// specific task id, open that task's own detail screen — landing on the
  /// tab's list and making the agent find the one they were notified about
  /// isn't "opening the connected page", it's just opening the app.
  ///
  /// A brand-new assignment (tapped from its full-screen alert notification,
  /// or the cold-launch/background-tap paths that never got to show that
  /// screen live) opens [IncomingTaskScreen] instead of jumping straight to
  /// the detail — so a delayed tap still gets the same Accept/Dismiss moment
  /// a live alert would have given.
  void _handleTap(Map<String, dynamic> data) {
    _refreshInbox();
    if (isUrgentAssignment(data)) {
      _openIncomingTask(data);
      return;
    }
    final tab = tabForPush(data);
    if (tab != null) _ref.read(homeTabProvider.notifier).state = tab;
    _openDetail(data);
  }

  void _openIncomingTask(Map<String, dynamic> data) {
    final tab = tabForPush(data);
    if (tab != null) _ref.read(homeTabProvider.notifier).state = tab;
    final navigator = rootNavigatorKey.currentState;
    navigator?.push(MaterialPageRoute<void>(
      builder: (_) => IncomingTaskScreen(data: data),
    ));
  }

  void _openDetail(Map<String, dynamic> data) {
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return;
    final widget = detailScreenForPush(data);
    if (widget == null) return;
    navigator.push(MaterialPageRoute<void>(builder: (_) => widget));
  }

  void _refreshInbox() {
    try {
      _ref.invalidate(notificationsProvider);
    } catch (_) {
      // provider not currently alive — the inbox reloads on next open anyway
    }
    // A push about a new assignment used to refresh ONLY the notification
    // inbox, so the task itself stayed missing from the agent's queues until
    // they pulled to refresh. Refresh the work queues too.
    try {
      _ref.read(taskSyncProvider).refreshNow();
    } catch (_) {
      // sync not started yet (push arrived pre-login) — nothing to refresh
    }
  }

  Future<void> _registerToken(String? token) async {
    if (token == null || token.isEmpty) return;
    try {
      await _api.post(
        '/notifications/device-token',
        data: {'token': token, 'platform': _platform()},
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Device token registration failed: $e');
    }
  }

  String _platform() {
    if (kIsWeb) return 'android';
    return Platform.isIOS ? 'ios' : 'android';
  }
}

/// FCM wrapper (permission, token, message streams).
final pushServiceProvider = Provider<PushService>((_) => PushService.create());

/// App-wide push orchestrator. Started by [PushGate] once the agent is
/// authenticated (and reset on logout).
final pushControllerProvider = Provider<PushController>(PushController.new);

/// Test seam: resolve the shell tab a push payload should deep-link to
/// (null = leave the current tab). See [PushController].
int? pushTabFor(Map<String, dynamic> data) => tabForPush(data);
