import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Starts/stops the persistent Android foreground service (see
/// core/services/background_service.dart) that keeps an on-duty agent's
/// location reaching dispatch even if the app itself is swiped away —
/// dispatch scoring (`_score` in assignment_engine.py) reads whichever GPS
/// ping is most recent, and the only ping that used to exist was the
/// active-delivery one, so it went stale the moment an agent finished their
/// last drop and just sat "available" waiting for the next.
///
/// A real foreground service (not just an in-app Timer) specifically because
/// a plain Dart Timer dies the instant Android kills the app process — the
/// exact case a swiped-away, still-on-duty agent needs covered. The service
/// itself does the actual pinging, in its own isolate; this is just the
/// on/off switch, wired to the availability toggle (dashboard_screen.dart).
class PresenceController {
  final _service = FlutterBackgroundService();

  // Every call here crosses a platform channel — fail soft. This is invoked
  // fire-and-forget from a `ref.listen` callback (dashboard_screen.dart)
  // whenever the agent's availability changes, so an unhandled rejection
  // here (e.g. the plugin channel not being registered, as in a widget-test
  // environment with no real platform) would surface as an uncaught async
  // error with no relation to whatever the agent was actually doing.
  Future<void> start() async {
    try {
      if (await _service.isRunning()) return;
      await _ensureBackgroundLocationPermission();
      await _service.startService();
    } catch (e) {
      if (kDebugMode) debugPrint('Presence service start failed: $e');
    }
  }

  Future<void> stop() async {
    try {
      if (!await _service.isRunning()) return;
      _service.invoke('stopService');
    } catch (e) {
      if (kDebugMode) debugPrint('Presence service stop failed: $e');
    }
  }

  /// Best-effort: escalate to "Allow all the time" so the service can still
  /// get a fix once there's no foreground Activity (a foreground SERVICE
  /// alone doesn't count as foreground for location purposes on Android 10+).
  /// Falls through quietly if the agent only grants "while using the app" —
  /// the service still runs, it just won't get fixes until they reopen the
  /// app, which the notification's "Waiting for a GPS fix…" makes visible.
  Future<void> _ensureBackgroundLocationPermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.whileInUse) {
        // Second call is what triggers Android's "Allow all the time" upgrade
        // prompt on most current versions once whileInUse is already granted.
        perm = await Geolocator.requestPermission();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Background location permission request failed: $e');
    }
  }
}

final presenceControllerProvider =
    Provider<PresenceController>((ref) => PresenceController());
