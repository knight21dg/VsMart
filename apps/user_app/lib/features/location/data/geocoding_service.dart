import 'package:geocoding/geocoding.dart' as native;

import '../../../core/network/api_client.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/entities/resolved_location.dart';

/// Reverse-geocodes GPS coordinates into a human-readable delivery area.
///
/// Strategy: first ask the VS Mart backend (`GET /geo/reverse`), which uses
/// Google when a key is configured. If the backend returns an empty `area`
/// (source "no_key"/"no_result"/"error"/"none"), fall back to the device's
/// native reverse geocoder so the user still sees their locality offline or
/// without a server key.
class GeocodingService {
  const GeocodingService(this._client);

  final ApiClient _client;

  /// Resolves [lat]/[lng] to a [ResolvedLocation]. Never throws — on total
  /// failure it returns a bare location carrying just the coordinates.
  Future<ResolvedLocation> reverse(double lat, double lng) async {
    final backend = await _reverseBackend(lat, lng);
    if (backend != null && backend.hasArea) return backend;

    // Backend had no usable area → try the on-device geocoder.
    final fallback = await _reverseNative(lat, lng);
    if (fallback != null && fallback.hasArea) return fallback;

    // Nothing resolved an area; return whatever the backend gave (it may still
    // hold city/state/pincode) or a bare coordinate-only location.
    return backend ??
        ResolvedLocation(latitude: lat, longitude: lng, source: 'none');
  }

  Future<ResolvedLocation?> _reverseBackend(double lat, double lng) async {
    try {
      final res = await _client.get<dynamic>(
        '/geo/reverse',
        query: {'lat': lat, 'lng': lng},
      );
      final raw = res.data;
      // Unwrap an optional {success,message,data} envelope.
      final map = raw is Map && raw['data'] is Map ? raw['data'] : raw;
      if (map is! Map) return null;
      return ResolvedLocation(
        latitude: lat,
        longitude: lng,
        area: (map['area'] ?? '').toString().trim(),
        city: (map['city'] ?? '').toString().trim(),
        state: (map['state'] ?? '').toString().trim(),
        pincode: (map['pincode'] ?? '').toString().trim(),
        formatted: (map['formatted'] ?? '').toString().trim(),
        source: (map['source'] ?? 'google').toString().trim(),
      );
    } catch (e) {
      AppLogger.w('geo/reverse backend failed: $e');
      return null;
    }
  }

  Future<ResolvedLocation?> _reverseNative(double lat, double lng) async {
    try {
      final marks = await native.placemarkFromCoordinates(lat, lng);
      if (marks.isEmpty) return null;
      final p = marks.first;
      final area = (p.subLocality?.trim().isNotEmpty ?? false)
          ? p.subLocality!.trim()
          : (p.locality?.trim() ?? '');
      final city = p.locality?.trim() ?? '';
      final state = p.administrativeArea?.trim() ?? '';
      final pincode = p.postalCode?.trim() ?? '';
      final formatted = [
        p.name,
        p.subLocality,
        p.locality,
        p.administrativeArea,
        p.postalCode,
      ]
          .where((e) => e != null && e.trim().isNotEmpty)
          .map((e) => e!.trim())
          .toSet()
          .join(', ');
      return ResolvedLocation(
        latitude: lat,
        longitude: lng,
        area: area,
        city: city,
        state: state,
        pincode: pincode,
        formatted: formatted,
        source: 'native',
      );
    } catch (e) {
      AppLogger.w('native reverse geocode failed: $e');
      return null;
    }
  }
}
