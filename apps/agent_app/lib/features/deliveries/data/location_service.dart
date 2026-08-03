import 'package:geolocator/geolocator.dart';

/// A single GPS fix (latitude/longitude + accuracy in metres).
class GeoFix {
  const GeoFix(this.latitude, this.longitude, {this.accuracyM = 0});
  final double latitude;
  final double longitude;
  final double accuracyM;
}

/// Real device-location source for the delivery flow (geolocator). Drives the
/// `/arrive` geofence, the proof-photo GPS tag, and the 15s `/deliveries/location`
/// ping. If permission is denied or GPS is off, falls back to the last known fix
/// (and, as a last resort, a caller-supplied fallback) so the flow never hard-stops
/// — the backend's 50 m check is the authority on whether `/arrive` succeeds.
class LocationService {
  GeoFix? _last;
  bool _deviceGps = true;

  void remember(GeoFix fix) => _last = fix;

  bool get hasDeviceGps => _deviceGps;

  /// Whether device GPS is usable right now (service on + permission granted),
  /// requesting permission if needed. Lets a screen prompt the agent to enable
  /// location BEFORE an action that depends on it (arrive geofence, GPS evidence)
  /// rather than silently falling back.
  Future<bool> ready() => _ensurePermission();

  Future<bool> _ensurePermission() async {
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
  }

  /// The best location currently available. Tries a live device fix first;
  /// [fallback] (typically the task destination) is only used if GPS is
  /// unavailable.
  Future<GeoFix?> current({GeoFix? fallback}) async {
    try {
      if (await _ensurePermission()) {
        final p = await Geolocator.getCurrentPosition(
          locationSettings:
              const LocationSettings(accuracy: LocationAccuracy.high),
        );
        final fix = GeoFix(p.latitude, p.longitude, accuracyM: p.accuracy);
        _last = fix;
        return fix;
      }
    } catch (_) {
      _deviceGps = false;
    }
    if (_last != null) return _last;
    if (fallback != null) {
      _last = fallback;
      return fallback;
    }
    return null;
  }
}
