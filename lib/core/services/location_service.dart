import 'package:geolocator/geolocator.dart';

/// Wraps [Geolocator] for permission handling and current-position lookup.
class LocationService {
  const LocationService();

  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  /// Ensures permission is granted, requesting it if needed.
  Future<bool> ensurePermission() async {
    if (!await isServiceEnabled()) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Returns the current position, or `null` if permission/service unavailable.
  Future<Position?> getCurrentPosition() async {
    if (!await ensurePermission()) return null;
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }

  double distanceMeters({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) =>
      Geolocator.distanceBetween(startLat, startLng, endLat, endLng);

  Future<void> openAppSettings() => Geolocator.openAppSettings();
}
