import 'package:dio/dio.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

/// Pretty request/response logging, enabled only outside production.
///
/// Wraps [PrettyDioLogger] so the rest of the app depends on our own type.
class LoggerInterceptor extends Interceptor {
  LoggerInterceptor({bool enabled = true})
      : _delegate = enabled
            ? PrettyDioLogger(
                requestHeader: true,
                requestBody: true,
                responseHeader: false,
                responseBody: true,
                error: true,
                compact: true,
                maxWidth: 100,
              )
            : null;

  final PrettyDioLogger? _delegate;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_delegate != null) {
      _delegate.onRequest(options, handler);
    } else {
      handler.next(options);
    }
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    if (_delegate != null) {
      _delegate.onResponse(response, handler);
    } else {
      handler.next(response);
    }
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (_delegate != null) {
      _delegate.onError(err, handler);
    } else {
      handler.next(err);
    }
  }
}
