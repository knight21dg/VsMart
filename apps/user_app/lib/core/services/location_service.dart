import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// Outcome of a permission check — lets callers distinguish a plain "denied"
/// (re-askable) from "denied forever" (must be sent to system settings).
enum LocationPermissionState { granted, denied, deniedForever, serviceOff }

/// Wraps [Geolocator] for permission handling and current-position lookup.
///
/// The whole app hard-locks behind a single position fix, so this is deliberately
/// resilient: a high-accuracy read is bounded by a timeout and falls back to the
/// last-known fix rather than returning null (which would brick the lock screen).
class LocationService {
  const LocationService();

  /// How long to wait for a fresh high-accuracy fix before falling back.
  static const Duration _fixTimeout = Duration(seconds: 12);

  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  /// Resolves the current permission/service state, requesting permission if it
  /// is merely [LocationPermission.denied] (not yet permanently denied).
  Future<LocationPermissionState> checkPermission() async {
    if (!await isServiceEnabled()) return LocationPermissionState.serviceOff;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    switch (permission) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationPermissionState.granted;
      case LocationPermission.deniedForever:
        return LocationPermissionState.deniedForever;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        return LocationPermissionState.denied;
    }
  }

  /// Ensures permission is granted, requesting it if needed.
  Future<bool> ensurePermission() async =>
      await checkPermission() == LocationPermissionState.granted;

  /// Returns the current position, or `null` if permission/service unavailable.
  ///
  /// Resilient by design: a fresh high-accuracy fix is bounded by [_fixTimeout];
  /// if it times out or errors (common indoors), we fall back to the device's
  /// last-known fix so a slow GPS doesn't hard-lock the customer out of the app.
  Future<Position?> getCurrentPosition() async {
    if (!await ensurePermission()) return null;
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: _fixTimeout,
        ),
      );
    } on TimeoutException {
      return _lastKnown();
    } catch (_) {
      // LocationServiceDisabledException, PositionUpdateException, platform
      // errors — try the last-known fix before giving up.
      return _lastKnown();
    }
  }

  Future<Position?> _lastKnown() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  double distanceMeters({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) =>
      Geolocator.distanceBetween(startLat, startLng, endLat, endLng);

  Future<void> openAppSettings() => Geolocator.openAppSettings();

  Future<void> openLocationSettings() => Geolocator.openLocationSettings();
}
