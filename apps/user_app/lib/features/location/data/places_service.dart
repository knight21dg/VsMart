import 'dart:math';

import 'package:dio/dio.dart';

import '../../../app/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/entities/place_suggestion.dart';
import '../domain/entities/resolved_location.dart';

/// The outcome of an autocomplete call — carries WHY it came back empty so the
/// UI can say "search is unavailable" instead of a misleading "no matches".
class PlacesSearchResult {
  const PlacesSearchResult(this.suggestions, this.source);

  const PlacesSearchResult.failed(this.source) : suggestions = const [];

  final List<PlaceSuggestion> suggestions;

  /// google | no_result | no_key | error | short | unreachable
  final String source;

  /// True when the search could not run (vs. genuinely matching nothing).
  bool get failed =>
      source == 'no_key' || source == 'error' || source == 'unreachable';
}

/// Google Places search.
///
/// Calls the **Places API (New) directly from the device** using the app's Maps
/// key. Direct is the right call here: the key is deliberately unrestricted
/// (one key for every surface — see MAPS_SETUP.md) and already ships inside the
/// APK for the Maps SDK, so proxying bought us nothing while *costing* us a hop
/// and — worse — an auth requirement: the backend `/geo/*` routes need a login,
/// so search was dead on the pre-login serviceability lock screen.
///
/// Falls back to the backend proxy when no key was compiled in
/// (`--dart-define=MAPS_API_KEY=...`), so a key-less build still searches.
///
/// Autocomplete + detail share a [sessionToken] so Google bills them as one
/// session. Nothing throws: autocomplete reports failure via
/// [PlacesSearchResult.failed] and detail returns null, so the UI can always
/// fall back to "use my current location" / pick-on-map.
class PlacesService {
  PlacesService(this._client, {Dio? google})
      : _google = google ??
            Dio(BaseOptions(
              // Google answers 4xx with a JSON error body we want to read.
              validateStatus: (s) => s != null && s < 500,
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
            ));

  final ApiClient _client;
  final Dio _google;

  static const _autocompleteUrl =
      'https://places.googleapis.com/v1/places:autocomplete';
  static const _detailBase = 'https://places.googleapis.com/v1/places';

  String get _key => AppConfig.instance.mapsApiKey;
  bool get _direct => _key.isNotEmpty;

  /// A fresh opaque session token for an autocomplete→detail search session.
  static String newSessionToken() {
    final r = Random();
    return '${DateTime.now().microsecondsSinceEpoch}-${r.nextInt(1 << 31)}';
  }

  Future<PlacesSearchResult> autocomplete(
    String query, {
    required String sessionToken,
  }) async {
    final q = query.trim();
    if (q.length < 2) return const PlacesSearchResult([], 'short');
    if (!_direct) return _autocompleteViaProxy(q, sessionToken);
    try {
      final res = await _google.post<dynamic>(
        _autocompleteUrl,
        data: {
          'input': q,
          'includedRegionCodes': ['in'],
          'sessionToken': sessionToken,
        },
        options: Options(headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': _key,
        }),
      );
      if (res.statusCode != 200) {
        AppLogger.w('places autocomplete ${res.statusCode}: ${res.data}');
        // A rejected key/API shouldn't kill search — the proxy may still work.
        return _autocompleteViaProxy(q, sessionToken);
      }
      final data = res.data;
      final suggestions = <PlaceSuggestion>[];
      for (final s in (data is Map ? (data['suggestions'] as List?) : null) ??
          const []) {
        final pp = (s as Map)['placePrediction'];
        if (pp is! Map || (pp['placeId'] ?? '').toString().isEmpty) continue;
        final sf = (pp['structuredFormat'] as Map?) ?? const {};
        final main = ((sf['mainText'] as Map?)?['text'] ??
                (pp['text'] as Map?)?['text'] ??
                '')
            .toString()
            .trim();
        suggestions.add(PlaceSuggestion(
          placeId: pp['placeId'].toString(),
          primary: main,
          secondary:
              ((sf['secondaryText'] as Map?)?['text'] ?? '').toString().trim(),
        ));
      }
      return PlacesSearchResult(
          suggestions, suggestions.isEmpty ? 'no_result' : 'google');
    } catch (e) {
      AppLogger.w('places autocomplete (direct) failed: $e');
      return _autocompleteViaProxy(q, sessionToken);
    }
  }

  /// Resolves a selected suggestion to coordinates + address parts. Returns null
  /// when it can't be resolved (no key / no result).
  Future<ResolvedLocation?> detail(
    String placeId, {
    required String sessionToken,
  }) async {
    if (!_direct) return _detailViaProxy(placeId, sessionToken);
    try {
      final res = await _google.get<dynamic>(
        '$_detailBase/$placeId',
        queryParameters: {'sessionToken': sessionToken},
        options: Options(headers: {
          'X-Goog-Api-Key': _key,
          // Ask only for what we use — field mask is REQUIRED and also caps cost.
          'X-Goog-FieldMask':
              'location,formattedAddress,addressComponents,displayName',
        }),
      );
      if (res.statusCode != 200 || res.data is! Map) {
        AppLogger.w('places detail ${res.statusCode}: ${res.data}');
        return _detailViaProxy(placeId, sessionToken);
      }
      final data = res.data as Map;
      final loc = data['location'] as Map?;
      final lat = _toDouble(loc?['latitude']);
      final lng = _toDouble(loc?['longitude']);
      if (lat == null || lng == null) return null;
      final comps = (data['addressComponents'] as List?) ?? const [];
      return ResolvedLocation(
        latitude: lat,
        longitude: lng,
        area: _component(comps, ['sublocality_level_1', 'sublocality', 'neighborhood']),
        city: _component(comps, ['locality', 'administrative_area_level_2']),
        state: _component(comps, ['administrative_area_level_1']),
        pincode: _component(comps, ['postal_code']),
        formatted: (data['formattedAddress'] ?? '').toString().trim(),
        source: 'google',
      );
    } catch (e) {
      AppLogger.w('places detail (direct) failed: $e');
      return _detailViaProxy(placeId, sessionToken);
    }
  }

  /// Pull a named component out of Places API (New) `addressComponents`
  /// (`longText`/`types`, unlike the legacy `long_name`).
  String _component(List<dynamic> comps, List<String> types) {
    for (final c in comps) {
      if (c is! Map) continue;
      final t = (c['types'] as List?)?.map((e) => e.toString()) ?? const [];
      if (types.any(t.contains)) return (c['longText'] ?? '').toString().trim();
    }
    return '';
  }

  // ── Backend `/geo` proxy fallback (key-less builds) ────────────────────────
  Future<PlacesSearchResult> _autocompleteViaProxy(
      String q, String sessionToken) async {
    try {
      final res = await _client.get<dynamic>(
        '/geo/places/autocomplete',
        query: {'q': q, 'session': sessionToken},
      );
      final map = _unwrap(res.data);
      final preds = (map?['predictions'] as List?) ?? const [];
      return PlacesSearchResult(
        preds
            .whereType<Map>()
            .map((p) => PlaceSuggestion(
                  placeId: (p['placeId'] ?? '').toString(),
                  primary:
                      (p['primary'] ?? p['description'] ?? '').toString().trim(),
                  secondary: (p['secondary'] ?? '').toString().trim(),
                ))
            .where((s) => s.placeId.isNotEmpty)
            .toList(),
        (map?['source'] ?? 'google').toString(),
      );
    } catch (e) {
      AppLogger.w('places autocomplete (proxy) failed: $e');
      return const PlacesSearchResult.failed('unreachable');
    }
  }

  Future<ResolvedLocation?> _detailViaProxy(
      String placeId, String sessionToken) async {
    try {
      final res = await _client.get<dynamic>(
        '/geo/places/detail',
        query: {'placeId': placeId, 'session': sessionToken},
      );
      final map = _unwrap(res.data);
      final lat = _toDouble(map?['lat']);
      final lng = _toDouble(map?['lng']);
      if (lat == null || lng == null) return null;
      return ResolvedLocation(
        latitude: lat,
        longitude: lng,
        area: (map?['area'] ?? '').toString().trim(),
        city: (map?['city'] ?? '').toString().trim(),
        state: (map?['state'] ?? '').toString().trim(),
        pincode: (map?['pincode'] ?? '').toString().trim(),
        formatted: (map?['formatted'] ?? '').toString().trim(),
        source: (map?['source'] ?? 'google').toString().trim(),
      );
    } catch (e) {
      AppLogger.w('places detail (proxy) failed: $e');
      return null;
    }
  }

  /// Unwrap an optional {success,message,data} envelope.
  Map<dynamic, dynamic>? _unwrap(dynamic raw) {
    final map = raw is Map && raw['data'] is Map ? raw['data'] : raw;
    return map is Map ? map : null;
  }

  double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
