import 'package:dio/dio.dart';

import '../../errors/error_handler.dart';

/// Normalizes every Dio error into a typed [Failure] and stashes it on
/// [DioException.error], so callers can read a clean domain error.
class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final failure = ErrorHandler.handle(err);
    handler.next(err.copyWith(error: failure));
  }
}
