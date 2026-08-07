import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../app/config/app_config.dart';
import '../../../../core/storage/token_storage.dart';
import '../../../../shared/providers/core_providers.dart';

/// A live agent position pushed over the order-tracking WebSocket.
class LiveTracking {
  const LiveTracking({
    required this.lat,
    required this.lng,
    this.eta,
    this.status,
  });

  final double lat;
  final double lng;
  final String? eta;
  final String? status;
}

/// The real road-following ETA (e.g. "18 min") the tracking map gets back from
/// the backend `/geo/route` Directions call, keyed by order id.
///
/// The map was already fetching this — a real, billed Directions request — and
/// dropping it on the floor, because its `onEta` callback had no call site. The
/// customer was shown `OrderTracking.eta` instead: the backend's straight-line
/// haversine distance at a flat 20 km/h, which ignores roads and traffic. This
/// carries the accurate figure to the headline.
final routeEtaProvider =
    StateProvider.family.autoDispose<String?, String>((ref, orderId) => null);

/// Derive the ws(s):// base from the http(s) API base (…/api/v1 → ws root).
String _wsBase(String apiBase) => apiBase
    .replaceFirst(RegExp(r'^http'), 'ws')
    .replaceFirst(RegExp(r'/api/v\d+/?$'), '');

/// The access token used for the handshake had a fixed 30-min lifetime and was
/// read ONCE before the reconnect loop started — so a delivery that ran long
/// enough for it to expire (or a socket that dropped and reconnected after
/// that point) kept dialling the backend with a now-dead token forever. The
/// consumer's `connect()` closes with 4403 on that, so the customer silently
/// fell all the way back to the 12s REST poll for the rest of the order with
/// no way to recover short of reopening the screen. Refreshing here — the same
/// `/auth/refresh` exchange [AuthInterceptor] does for REST 401s — before every
/// (re)connect attempt keeps the socket alive across the whole delivery.
Future<String?> _freshToken(TokenStorage storage) async {
  if (await storage.hasValidToken()) return storage.getAccessToken();
  final refresh = await storage.getRefreshToken();
  if (refresh == null || refresh.isEmpty) return null;
  try {
    final res = await Dio(BaseOptions(baseUrl: AppConfig.instance.apiBaseUrl))
        .post<dynamic>('/auth/refresh', data: {'refresh': refresh});
    final body = res.data;
    final data = body is Map && body['data'] is Map
        ? Map<String, dynamic>.from(body['data'] as Map)
        : (body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{});
    final access = data['access_token'] as String?;
    if (access == null || access.isEmpty) return null;
    await storage.saveTokens(
      accessToken: access,
      refreshToken: data['refresh_token'] as String?,
    );
    return access;
  } catch (_) {
    // Transient (offline/5xx) — keep the existing (possibly stale) token
    // rather than giving up; the next reconnect attempt tries again.
    return storage.getAccessToken();
  }
}

/// Streams the agent's live position for an in-flight order over the backend
/// WebSocket (`ws/orders/<id>/tracking`). The REST poll on the tracking screen
/// stays as the initial load + fallback; this just moves the rider smoothly in
/// between. Auto-reconnects with a short backoff while anyone is watching.
final liveTrackingProvider =
    StreamProvider.family.autoDispose<LiveTracking, String>((ref, orderId) async* {
  final storage = ref.watch(tokenStorageProvider);

  WebSocketChannel? channel;
  // The reconnect loop has no yield point on the failure path, so a disposed
  // provider would never be suspended by the cancelled subscription: closing the
  // socket in onDispose just ended the `await for`, and the loop slept and dialled
  // again — forever, per abandoned tracking screen. Dispose has to be explicit.
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    channel?.sink.close();
  });

  // Back off on a server that's down instead of reconnecting every 3s for as long
  // as the screen is open.
  const minBackoff = Duration(seconds: 3);
  const maxBackoff = Duration(seconds: 30);
  var backoff = minBackoff;

  while (!disposed) {
    try {
      final token = await _freshToken(storage);
      if (token == null || token.isEmpty) {
        // No session to authenticate with at all (signed out) — nothing to
        // retry into; stop rather than spin.
        return;
      }
      final uri = Uri.parse(
        '${_wsBase(AppConfig.instance.apiBaseUrl)}/ws/orders/$orderId/tracking'
        '?token=${Uri.encodeComponent(token)}',
      );
      channel = WebSocketChannel.connect(uri);
      await for (final raw in channel.stream) {
        if (disposed) return;
        if (raw is! String) continue;
        final msg = jsonDecode(raw);
        if (msg is! Map || msg['type'] != 'tracking') continue;
        final d = msg['data'];
        if (d is! Map) continue;
        final lat = (d['latitude'] as num?)?.toDouble();
        final lng = (d['longitude'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          // A message got through, so the connection is healthy again.
          backoff = minBackoff;
          yield LiveTracking(
            lat: lat,
            lng: lng,
            eta: d['eta'] as String?,
            status: d['status'] as String?,
          );
        }
      }
    } catch (_) {
      // fall through to reconnect
    }
    if (disposed) return;
    await Future<void>.delayed(backoff);
    final next = backoff * 2;
    backoff = next > maxBackoff ? maxBackoff : next;
  }
});
