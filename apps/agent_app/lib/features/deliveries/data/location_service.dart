import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// A single GPS fix (latitude/longitude + accuracy in metres).
class GeoFix {
  const GeoFix(this.latitude, this.longitude, {this.accuracyM = 0});
  final double latitude;
  final double longitude;
  final double accuracyM;
}

/// Real device-location source for the delivery flow (geolocator). Drives the
/// `/arrive` geofence, the proof-photo GPS tag, and the 15s
/// `/deliveries/location` ping.
///
/// **This only ever reports where the DEVICE has actually been.** It used to
/// take a caller-supplied `fallback` — in practice the task's destination — and
/// return that whenever GPS was off or denied. Every caller then sent the
/// delivery address as the agent's own position, which meant:
///   • `/arrive` cleared the backend's 100 m geofence from anywhere, simply by
///     turning location off — the one control on "did the rider actually go
///     there" was being answered by the phone with the expected answer;
///   • the proof-of-delivery photo was stamped with the destination rather than
///     where it was taken;
///   • `/deliveries/location` breadcrumbs (dispatch scoring, audit trail) were
///     fed coordinates the device never visited.
/// A stale-but-real last fix is still honest data, so it stays as a fallback; a
/// fabricated one is not, so it is gone. Callers that need proof of presence use
/// [currentLive] and prompt the agent to enable GPS when it returns null.
class LocationService {
  /// A fix attempt that hasn't returned by now is treated as "no fix". Without
  /// it the geolocator future can hang indefinitely indoors or with a cold
  /// antenna — the agent taps "Arrive" and nothing happens at all, which reads
  /// as a frozen app.
  static const fixTimeout = Duration(seconds: 12);

  GeoFix? _last;
  bool _deviceGps = true;

  void remember(GeoFix fix) => _last = fix;

  /// Whether the last permission/service check found GPS usable.
  bool get hasDeviceGps => _deviceGps;

  /// The most recent real fix this device produced, if any.
  GeoFix? get lastKnown => _last;

  /// Whether device GPS is usable right now (service on + permission granted),
  /// requesting permission if needed. Lets a screen prompt the agent to enable
  /// location BEFORE an action that depends on it.
  Future<bool> ready() => _ensurePermission();

  Future<bool> _ensurePermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _deviceGps = false;
        return false;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      final ok = perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse;
      _deviceGps = ok;
      return ok;
    } catch (_) {
      // Platform channel unavailable, or a permission-dialog race — treat as
      // "no GPS" rather than throwing into a caller mid-flow.
      _deviceGps = false;
      return false;
    }
  }

  /// A LIVE fix from the device, or null. Never cached, never substituted — use
  /// this for anything the backend or an auditor treats as evidence that the
  /// agent was physically somewhere (arrival geofence, photo GPS stamp).
  Future<GeoFix?> currentLive() async {
    try {
      if (!await _ensurePermission()) return null;
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: fixTimeout,
        ),
      ).timeout(fixTimeout);
      final fix = GeoFix(p.latitude, p.longitude, accuracyM: p.accuracy);
      _last = fix;
      return fix;
    } on TimeoutException {
      return null;
    } catch (_) {
      _deviceGps = false;
      return null;
    }
  }

  /// Best available REAL location: a live fix, else the last one this device
  /// produced. Null when the device has never had a fix. For non-authoritative
  /// uses (centring a map, a breadcrumb ping) — not for proving presence.
  Future<GeoFix?> current() async => await currentLive() ?? _last;
}
