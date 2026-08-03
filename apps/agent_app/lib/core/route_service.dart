import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'api.dart';
import 'providers.dart';

/// A road route + ETA between two points, resolved by the backend `/geo/route`
/// proxy (Google Routes API via the server key — the app's app-restricted key
/// can't call the web service). Never throws; returns an empty result on any
/// failure so callers keep a marker-only fallback.
class RouteResult {
  const RouteResult({
    this.points = const [],
    this.distanceText = '',
    this.durationText = '',
  });

  final List<LatLng> points;

  /// e.g. "3.4 km".
  final String distanceText;

  /// Human ETA, e.g. "12 min".
  final String durationText;

  bool get hasPath => points.length > 1;
}

class RouteService {
  const RouteService(this._api);

  final Api _api;

  Future<RouteResult> route({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    String mode = 'DRIVE',
  }) async {
    try {
      final res = await _api.get(
        '/geo/route?origin=$originLat,$originLng&dest=$destLat,$destLng&mode=$mode',
      );
      final raw = res.data;
      final map = raw is Map && raw['data'] is Map ? raw['data'] : raw;
      if (map is! Map) return const RouteResult();
      final meters = (map['distanceMeters'] as num?)?.toInt();
      return RouteResult(
        points: decodePolyline((map['encodedPolyline'] ?? '').toString()),
        distanceText: meters != null ? _km(meters) : '',
        durationText: (map['durationText'] ?? '').toString(),
      );
    } catch (_) {
      return const RouteResult();
    }
  }

  static String _km(int meters) {
    final km = meters / 1000;
    return km >= 10 ? '${km.toStringAsFixed(0)} km' : '${km.toStringAsFixed(1)} km';
  }
}

final routeServiceProvider =
    Provider<RouteService>((ref) => RouteService(ref.watch(apiProvider)));

/// Decode a Google "encoded polyline" string into coordinates.
List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  var index = 0, lat = 0, lng = 0;
  while (index < encoded.length) {
    int b, shift = 0, result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return points;
}
