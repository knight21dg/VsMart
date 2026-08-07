import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/app_logger.dart';
import '../../../shared/providers/core_providers.dart';

/// A road route + ETA between two points, resolved by the backend `/geo/route`
/// proxy (Google Routes API via the server key).
class RouteResult {
  const RouteResult({
    this.encodedPolyline = '',
    this.distanceMeters,
    this.durationSeconds,
    this.durationText = '',
  });

  final String encodedPolyline;
  final int? distanceMeters;
  final int? durationSeconds;

  /// Human ETA, e.g. "18 min".
  final String durationText;

  bool get hasPath => encodedPolyline.isNotEmpty;
}

/// Fetches the real driving route (encoded polyline + ETA) from the backend so
/// order tracking draws the road path instead of a straight/curved guess. The
/// backend uses the server Maps key — the app's Android-restricted key can't call
/// the Routes web service. Never throws; returns an empty result on any failure so
/// the caller keeps its local fallback path.
class RouteService {
  const RouteService(this._client);

  final ApiClient _client;

  Future<RouteResult> route({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    try {
      final res = await _client.get<dynamic>(
        '/geo/route',
        query: {'origin': '$originLat,$originLng', 'dest': '$destLat,$destLng'},
      );
      final raw = res.data;
      final map = raw is Map && raw['data'] is Map ? raw['data'] : raw;
      if (map is! Map) return const RouteResult();
      return RouteResult(
        encodedPolyline: (map['encodedPolyline'] ?? '').toString(),
        distanceMeters: (map['distanceMeters'] as num?)?.toInt(),
        durationSeconds: (map['durationSeconds'] as num?)?.toInt(),
        durationText: (map['durationText'] ?? '').toString(),
      );
    } catch (e) {
      AppLogger.w('geo/route failed: $e');
      return const RouteResult();
    }
  }
}

final routeServiceProvider = Provider<RouteService>(
  (ref) => RouteService(ref.watch(apiClientProvider)),
);
