import 'package:dio/dio.dart';

import '../../../app/config/app_config.dart';
import '../../storage/token_storage.dart';

/// Attaches the bearer token to outgoing requests and transparently refreshes an
/// expired access token on a 401 — retrying the original request — before falling
/// back to a session invalidation. This keeps users signed in across app restarts
/// (the short-lived access token is renewed via the rotating refresh token).
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.tokenStorage,
    this.onUnauthorized,
  });

  final TokenStorage tokenStorage;
  final Future<void> Function()? onUnauthorized;

  /// Header flag a request can set to skip token injection (e.g. login/otp).
  static const String skipAuthHeader = 'x-skip-auth';

  /// Marks a request that has already been retried after a refresh, so a second
  /// 401 doesn't loop.
  static const String _retriedFlag = 'x-auth-retried';

  /// Bare client (no interceptors) used to call `/auth/refresh` and to replay the
  /// original request, so neither re-enters this interceptor.
  late final Dio _bare = Dio(
    BaseOptions(baseUrl: AppConfig.instance.apiBaseUrl),
  );

  /// De-dupes concurrent refreshes — many providers hydrate at once on cold
  /// start; without this they'd each spend the (rotating) refresh token and all
  /// but the first would fail.
  Future<(String?, _RefreshOutcome)>? _inFlightRefresh;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.headers.remove(skipAuthHeader) == true) {
      return handler.next(options);
    }
    final token = await tokenStorage.getAccessToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final req = err.requestOptions;
    final is401 = err.response?.statusCode == 401;
    final alreadyRetried = req.extra[_retriedFlag] == true;
    // Never try to refresh on the auth endpoints themselves (login/otp/refresh).
    final isAuthCall = req.path.contains('/auth/');

    if (!is401 || alreadyRetried || isAuthCall) {
      return handler.next(err);
    }

    // No stored token → nothing to refresh with. For a guest this 401 just means
    // the endpoint needs auth. But notify the session layer BEFORE surfacing:
    // if the app *believes* it is signed in with no tokens behind it (the
    // zombie-session split — e.g. a backup restore brought the logged-in flag
    // back without the Keystore-held tokens), nothing else would ever tear the
    // broken session down, and every personal screen bounces forever. The
    // callback checks the session state itself, so a genuine guest is a no-op.
    final hasToken = (await tokenStorage.getAccessToken())?.isNotEmpty ?? false;
    if (!hasToken) {
      await onUnauthorized?.call();
      return handler.next(err);
    }

    final (newAccess, outcome) = await _refresh();
    if (newAccess == null) {
      // Only tear the session down when the SERVER rejected the refresh token —
      // i.e. it is genuinely expired or revoked and re-login is the only way out.
      //
      // A network blip used to land here too, and clearing on it was
      // catastrophic: the refresh token was destroyed, so every later 401 bailed
      // at the `hasToken` check without even attempting a refresh. The customer
      // was silently logged out — mid-checkout, "Place Order" just bounced them
      // to login — and stayed broken until they signed in again.
      if (outcome == _RefreshOutcome.rejected) {
        await tokenStorage.clear();
        await onUnauthorized?.call();
      }
      return handler.next(err);
    }

    // Replay the original request once, with the fresh token.
    try {
      req.extra[_retriedFlag] = true;
      req.headers['Authorization'] = 'Bearer $newAccess';
      final response = await _bare.fetch<dynamic>(req);
      return handler.resolve(response);
    } catch (_) {
      return handler.next(err);
    }
  }

  /// Exchange the refresh token for a new access token (rotating). Returns the
  /// new access token plus WHY it failed, so the caller can tell a dead session
  /// apart from a flaky network. Concurrency-safe.
  Future<(String?, _RefreshOutcome)> _refresh() {
    return _inFlightRefresh ??=
        _doRefresh().whenComplete(() => _inFlightRefresh = null);
  }

  Future<(String?, _RefreshOutcome)> _doRefresh() async {
    final refresh = await tokenStorage.getRefreshToken();
    if (refresh == null || refresh.isEmpty) {
      // Nothing to refresh with — the session really is gone.
      return (null, _RefreshOutcome.rejected);
    }
    try {
      final res = await _bare.post<dynamic>(
        '/auth/refresh',
        data: {'refresh': refresh},
      );
      final body = res.data;
      final data = body is Map && body['data'] is Map
          ? Map<String, dynamic>.from(body['data'] as Map)
          : (body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{});
      final access = data['access_token'] as String?;
      final newRefresh = data['refresh_token'] as String?;
      if (access == null || access.isEmpty) {
        return (null, _RefreshOutcome.rejected);
      }
      await tokenStorage.saveTokens(
        accessToken: access,
        refreshToken: newRefresh,
      );
      return (access, _RefreshOutcome.success);
    } on DioException catch (e) {
      // 400/401/403 => the refresh token is genuinely bad. Anything else
      // (timeout, connection error, 5xx) is transient: keep the session so the
      // customer can retry instead of being logged out by a dropped packet.
      final code = e.response?.statusCode ?? 0;
      final rejected = code == 400 || code == 401 || code == 403;
      return (null, rejected ? _RefreshOutcome.rejected
                             : _RefreshOutcome.unavailable);
    } catch (_) {
      return (null, _RefreshOutcome.unavailable);
    }
  }
}

/// Why a token refresh didn't produce a new access token.
enum _RefreshOutcome {
  success,

  /// The server refused the refresh token — expired or revoked. Re-login needed.
  rejected,

  /// Couldn't reach the server (offline, timeout, 5xx). The session may well
  /// still be valid, so it must NOT be torn down.
  unavailable,
}
