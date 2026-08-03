import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'env.dart';
import 'token_store.dart';

/// Thin Dio wrapper for the agent app. Attaches the bearer token, refreshes it
/// on 401 via the rotating `/auth/refresh`, and unwraps the `{success,message,
/// data}` envelope the backend returns. `onLogout` fires when refresh fails.
///
/// NB: `validateStatus: s < 500` lets 4xx through as a *response* (not a Dio
/// error) so callers can convert the actionable envelope via [ensureOk]. Because
/// a 401 is therefore not an error either, token refresh is handled in the
/// `onResponse` hook (not `onError`), or it would never fire.
class Api {
  /// [dio] / [bare] are injectable test seams; production leaves them null and
  /// the real, interceptor-wired clients are built here.
  Api(this._tokens, {this.onLogout, Dio? dio, Dio? bare})
      : _bare = bare ??
            Dio(BaseOptions(baseUrl: Env.apiBaseUrl, validateStatus: _under500)) {
    _dio = dio ??
        Dio(BaseOptions(
          baseUrl: Env.apiBaseUrl,
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 20),
          validateStatus: _under500,
        ));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        if (options.extra['noAuth'] != true) {
          final t = await _tokens.access;
          if (t != null && t.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $t';
          }
        }
        handler.next(options);
      },
      // 401 arrives here (it's < 500, so not an onError). Refresh + retry once;
      // on refresh failure, clear tokens and sign out.
      onResponse: (response, handler) async {
        final req = response.requestOptions;
        final needsRefresh = response.statusCode == 401 &&
            req.extra['retried'] != true &&
            req.extra['noAuth'] != true &&
            !req.path.contains('/auth/');
        if (!needsRefresh) return handler.next(response);

        final access = await _refresh();
        if (access == null) {
          await _tokens.clear();
          await onLogout?.call();
          return handler.next(response); // let the 401 surface to ensureOk
        }
        try {
          req.extra['retried'] = true;
          req.headers['Authorization'] = 'Bearer $access';
          final res = await _bare.fetch<dynamic>(req);
          return handler.resolve(res);
        } catch (_) {
          return handler.next(response);
        }
      },
    ));
  }

  static bool _under500(int? s) => s != null && s < 500;

  final TokenStore _tokens;
  final Future<void> Function()? onLogout;
  late final Dio _dio;
  // Interceptor-free client for refresh + retry; same 4xx-as-response policy so a
  // retried request's envelope reaches ensureOk instead of throwing.
  final Dio _bare;
  Future<String?>? _inFlight;

  /// Throw an [ApiException] carrying the backend envelope if [res] is a non-2xx
  /// (Dio's validateStatus lets 4xx through as data); otherwise return it.
  /// Every repository call path should route through this.
  Response<dynamic> ensureOk(Response<dynamic> res) {
    if ((res.statusCode ?? 0) >= 400) {
      throw ApiException.fromResponse(res);
    }
    return res;
  }

  // ── envelope helpers ──
  Map<String, dynamic> obj(dynamic raw) {
    final d = raw is Map && raw['data'] is Map ? raw['data'] : raw;
    return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
  }

  List<Map<String, dynamic>> list(dynamic raw) {
    final d = raw is Map ? raw['data'] : raw;
    final l = d is List ? d : const [];
    return l.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Response<dynamic>> get(String path, {bool noAuth = false}) =>
      _dio.get<dynamic>(path, options: Options(extra: {'noAuth': noAuth}));

  Future<Response<dynamic>> post(String path, {Object? data, bool noAuth = false}) =>
      _dio.post<dynamic>(path,
          data: data, options: Options(extra: {'noAuth': noAuth}));

  Future<Response<dynamic>> put(String path, {Object? data, bool noAuth = false}) =>
      _dio.put<dynamic>(path,
          data: data, options: Options(extra: {'noAuth': noAuth}));

  Future<Response<dynamic>> patch(String path, {Object? data, bool noAuth = false}) =>
      _dio.patch<dynamic>(path,
          data: data, options: Options(extra: {'noAuth': noAuth}));

  /// Multipart POST (e.g. file uploads). Dio sets the multipart content type
  /// from the [FormData] body; auth + refresh flow through the interceptors.
  Future<Response<dynamic>> postMultipart(String path, FormData form,
          {bool noAuth = false}) =>
      _dio.post<dynamic>(path,
          data: form, options: Options(extra: {'noAuth': noAuth}));

  /// Fetch raw bytes with auth (e.g. a permission-gated KYC document image).
  /// Throws an [ApiException] on non-2xx.
  Future<List<int>> bytes(String path) async {
    final res = await _dio.get<List<int>>(
      path,
      options: Options(responseType: ResponseType.bytes),
    );
    ensureOk(res);
    return res.data ?? const <int>[];
  }

  Future<String?> _refresh() => _inFlight ??=
      _doRefresh().whenComplete(() => _inFlight = null);

  Future<String?> _doRefresh() async {
    try {
      final r = await _tokens.refresh;
      if (r == null || r.isEmpty) return null;
      final res = await _bare.post<dynamic>('/auth/refresh', data: {'refresh': r});
      final d = obj(res.data);
      final access = d['access_token'] as String?;
      if (access == null || access.isEmpty) return null;
      await _tokens.save(access: access, refresh: d['refresh_token'] as String?);
      return access;
    } catch (_) {
      return null;
    }
  }
}
