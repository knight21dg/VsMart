import 'package:dio/dio.dart';

import '../../app/config/app_config.dart';
import '../../app/constants/app_constants.dart';
import '../storage/token_storage.dart';
import 'interceptors/auth_interceptor.dart';
import 'interceptors/error_interceptor.dart';
import 'interceptors/logger_interceptor.dart';

/// Configured [Dio] facade for VS Mart. All repositories talk to the backend
/// through this client; it owns base options and the interceptor chain.
class ApiClient {
  ApiClient({
    required TokenStorage tokenStorage,
    Future<void> Function()? onUnauthorized,
    Dio? dio,
  }) : _dio = dio ?? Dio() {
    final config = AppConfig.instance;
    _dio.options = BaseOptions(
      baseUrl: config.apiBaseUrl,
      connectTimeout: const Duration(milliseconds: AppConstants.connectTimeout),
      receiveTimeout: const Duration(milliseconds: AppConstants.receiveTimeout),
      sendTimeout: const Duration(milliseconds: AppConstants.sendTimeout),
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
      // Only 2xx is a success. 4xx/5xx must raise a DioException so the
      // ErrorInterceptor maps them to a typed Failure (and the AuthInterceptor
      // can refresh on 401). Previously this allowed <500 through, so error
      // bodies were parsed as success — e.g. a 400 "invalid OTP" was decoded as
      // an auth token, crashing with "type 'null' is not a subtype of 'String'".
      validateStatus: (status) => status != null && status >= 200 && status < 300,
    );

    _dio.interceptors.addAll([
      AuthInterceptor(
        tokenStorage: tokenStorage,
        onUnauthorized: onUnauthorized,
      ),
      ErrorInterceptor(),
      LoggerInterceptor(enabled: config.enableLogging),
    ]);
  }

  final Dio _dio;

  Dio get raw => _dio;

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? query,
    Options? options,
    CancelToken? cancelToken,
  }) =>
      _dio.get<T>(
        path,
        queryParameters: query,
        options: options,
        cancelToken: cancelToken,
      );

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    Options? options,
    CancelToken? cancelToken,
  }) =>
      _dio.post<T>(
        path,
        data: data,
        queryParameters: query,
        options: options,
        cancelToken: cancelToken,
      );

  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    Options? options,
  }) =>
      _dio.put<T>(path, data: data, queryParameters: query, options: options);

  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    Options? options,
  }) =>
      _dio.patch<T>(path, data: data, queryParameters: query, options: options);

  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    Options? options,
  }) =>
      _dio.delete<T>(path, data: data, queryParameters: query, options: options);

  /// Build [Options] that bypass the auth header (for public endpoints).
  static Options noAuth() =>
      Options(headers: {AuthInterceptor.skipAuthHeader: true});
}
