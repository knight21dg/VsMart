import 'dart:async';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

import '../active_task_store.dart';
import '../env.dart';
import '../token_store.dart';

const _presenceChannelId = 'vsmart_presence';
const _presenceNotificationId = 778899;

/// Registers the Android foreground service used to keep an on-duty agent's
/// location reaching dispatch even if the app itself is swiped away — call
/// once at startup (configuring is cheap and idempotent; nothing actually
/// runs until [PresenceController] calls `startService()`).
///
/// This is a real persistent service (its own always-visible notification,
/// `foregroundServiceType="location"` in AndroidManifest.xml) rather than an
/// in-app Timer, specifically because a plain Dart Timer dies the instant
/// Android kills the app process — which is exactly the case a swiped-away,
/// still-on-duty agent needs covered.
Future<void> initializeBackgroundService() async {
  const channel = AndroidNotificationChannel(
    _presenceChannelId,
    'On-duty presence',
    description: "Keeps your location visible to dispatch while you're on duty",
    // Deliberately quiet (no sound/heads-up) — this is a persistent status
    // notification, not an alert. The urgent-task channel is separate.
    importance: Importance.low,
  );
  final local = FlutterLocalNotificationsPlugin();
  await local.initialize(const InitializationSettings(
    android: AndroidInitializationSettings('ic_notification'),
  ));
  await local
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await FlutterBackgroundService().configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onServiceStart,
      // Started explicitly by PresenceController when the agent goes
      // available, not on app launch or device boot.
      autoStart: false,
      autoStartOnBoot: false,
      isForegroundMode: true,
      notificationChannelId: _presenceChannelId,
      initialNotificationTitle: 'VS Mart Agent — On duty',
      initialNotificationContent: 'Starting…',
      foregroundServiceNotificationId: _presenceNotificationId,
      foregroundServiceTypes: [AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(autoStart: false),
  );
}

/// The service isolate's entry point. Runs independently of the main app
/// isolate/UI — must re-register plugins itself ([DartPluginRegistrant]) and
/// can't reach Riverpod providers, so it goes straight to [TokenStore] + a
/// bare [Dio] rather than the app's usual repo layer.
@pragma('vm:entry-point')
void onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on('stopService').listen((_) => service.stopSelf());
  }

  // Real fixes only, same rule as location_service.dart — but unlike a fresh
  // isolate, this one lives for as long as the service runs, so it can
  // remember its own last good fix across ticks and fall back to it instead
  // of giving up. Without this, a stationary/indoor agent (a store counter,
  // home, waiting between deliveries — exactly when "online" but not moving)
  // could fail to get a fresh HIGH-accuracy fix inside the deadline on every
  // single tick, forever, and the notification would sit on "Waiting for a
  // GPS fix…" the whole time the agent is online, not occasionally.
  Position? lastFix;

  Future<void> tick() async {
    final posted = await _pingOnce(lastFix: lastFix, remember: (f) => lastFix = f);
    if (service is AndroidServiceInstance &&
        await service.isForegroundService()) {
      final now = DateTime.now();
      final hh = now.hour.toString().padLeft(2, '0');
      final mm = now.minute.toString().padLeft(2, '0');
      service.setForegroundNotificationInfo(
        title: 'VS Mart Agent — On duty',
        content: posted ? 'Location shared · $hh:$mm' : 'Waiting for a GPS fix…',
      );
    }
  }

  await tick();
  Timer.periodic(const Duration(seconds: 90), (_) => tick());
}

/// One presence ping: a GPS fix (best-effort — silently skipped if location
/// is unavailable/denied) posted to the same `/deliveries/location`
/// path [PresenceController] used to call directly. Refreshes the access
/// token once on a 401, mirroring api.dart's own retry-once policy, since a
/// service that outlives the 30-min token lifetime would otherwise start
/// silently failing every ping.
///
/// Task-less by default (an available agent between deliveries has no task
/// to attach), but includes [ActiveTaskStore]'s current value when one is
/// set — an agent `out_for_delivery` whose app gets backgrounded or killed
/// still has this 90s tick to fall back on once the foreground 15s
/// breadcrumb (delivery_detail_screen.dart) stops, so the customer's live
/// tracking doesn't just freeze for the rest of the trip.
///
/// Fix acquisition has a real fallback chain, same honesty rule as
/// location_service.dart (real data or nothing — never a fabricated
/// position): a fresh MEDIUM-accuracy fix (HIGH routinely never resolves
/// indoors/stationary within any reasonable deadline — an agent sitting at
/// a store counter or at home "online" between deliveries is exactly the
/// common case, not an edge case), else [lastFix] (this isolate's own last
/// good fix — it lives for as long as the service runs, so this genuinely
/// carries across ticks), else the OS's own last-known position. Only if
/// all three come up empty does the ping — and the "Waiting for a GPS
/// fix…" notification — actually skip. Before this fell straight to that
/// last resort on a single HIGH-accuracy attempt with no memory at all, so
/// a stationary indoor agent could get stuck showing "Waiting for a GPS
/// fix…" on every tick, indefinitely, for the entire time they're online.
Future<bool> _pingOnce({
  Position? lastFix,
  required void Function(Position) remember,
}) async {
  try {
    final tokens = TokenStore();
    var access = await tokens.access;
    if (access == null || access.isEmpty) return false;
    final taskId = await ActiveTaskStore().current;

    // Bounded: an unbounded fix request can hang for the whole 90 s tick (and
    // beyond), stacking one never-completing location request per tick while
    // the notification still claims the agent is being tracked.
    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 20),
        ),
      ).timeout(const Duration(seconds: 25));
      remember(position);
    } catch (_) {
      position = lastFix ?? await Geolocator.getLastKnownPosition();
    }
    if (position == null) return false;
    // Closures capture by reference, so the null check above doesn't promote
    // `position` inside `post` below — bind it to a non-nullable local instead.
    final fix = position;

    final dio = Dio(BaseOptions(
      baseUrl: Env.apiBaseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      validateStatus: (_) => true,
    ));
    Future<Response<dynamic>> post(String token) => dio.post<dynamic>(
          '/deliveries/location',
          data: {
            'latitude': fix.latitude,
            'longitude': fix.longitude,
            'accuracy_m': fix.accuracy,
            if (taskId != null && taskId.isNotEmpty) 'task_id': taskId,
          },
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );

    var res = await post(access);
    if (res.statusCode == 401) {
      final refresh = await tokens.refresh;
      if (refresh == null || refresh.isEmpty) return false;
      final refreshRes = await dio.post<dynamic>(
          '/auth/refresh', data: {'refresh': refresh});
      final body = refreshRes.data;
      final data = body is Map && body['data'] is Map
          ? Map<String, dynamic>.from(body['data'] as Map)
          : (body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{});
      final newAccess = data['access_token'] as String?;
      if (newAccess == null || newAccess.isEmpty) return false;
      await tokens.save(access: newAccess, refresh: data['refresh_token'] as String?);
      access = newAccess;
      res = await post(access);
    }
    return res.statusCode != null && res.statusCode! < 400;
  } catch (_) {
    return false;
  }
}
