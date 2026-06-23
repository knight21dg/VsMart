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
  Future<String?>? _inFlightRefresh;

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

    // No stored session → this 401 just means the endpoint needs auth (e.g. a
    // guest browsing the app). Don't attempt a refresh or tear down a session
    // that never existed — simply surface the error.
    final hasToken = (await tokenStorage.getAccessToken())?.isNotEmpty ?? false;
    if (!hasToken) {
      return handler.next(err);
    }

    final newAccess = await _refresh();
    if (newAccess == null) {
      await tokenStorage.clear();
      await onUnauthorized?.call();
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
  /// new access token, or null if refresh isn't possible. Concurrency-safe.
  Future<String?> _refresh() {
    return _inFlightRefresh ??=
        _doRefresh().whenComplete(() => _inFlightRefresh = null);
  }

  Future<String?> _doRefresh() async {
    try {
      final refresh = await tokenStorage.getRefreshToken();
      if (refresh == null || refresh.isEmpty) return null;
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
      if (access == null || access.isEmpty) return null;
      await tokenStorage.saveTokens(
        accessToken: access,
        refreshToken: newRefresh,
      );
      return access;
    } catch (_) {
      return null;
    }
  }
}
