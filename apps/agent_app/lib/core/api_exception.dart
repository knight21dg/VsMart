import 'package:dio/dio.dart';

/// The backend actionable-error envelope, as a throwable.
///
/// Every non-2xx API response is converted to one of these (Dio's
/// `validateStatus: s < 500` lets 4xx through as a normal response, so
/// [Api.ensureOk] turns it into this). The UI surfaces [display] + [nextStep]
/// instead of a generic string. Feature-specific subclasses
/// (`DeliveryApiException`, …) extend this so `catch`/`is` checks keep working.
class ApiException implements Exception {
  ApiException({
    required this.code,
    required this.title,
    required this.message,
    this.nextStep,
    this.action,
    this.statusCode,
  });

  final String code;
  final String title;
  final String message;
  final String? nextStep;
  final String? action;
  final int? statusCode;

  factory ApiException.fromResponse(Response<dynamic>? res) {
    final f = parse(res);
    return ApiException(
      code: f.code, title: f.title, message: f.message,
      nextStep: f.nextStep, action: f.action, statusCode: f.statusCode,
    );
  }

  /// Parse the backend envelope `{code,title,message,nextStep,action,error:{…}}`
  /// into plain fields (shared by every subclass factory).
  static ({
    String code,
    String title,
    String message,
    String? nextStep,
    String? action,
    int? statusCode,
  }) parse(Response<dynamic>? res) {
    final data = res?.data;
    final status = res?.statusCode;
    if (data is Map) {
      final err = data['error'];
      final errMap = err is Map ? err : const {};
      final code = _str(_firstNonEmpty(data['code'], errMap['code'])).toUpperCase();
      final message = _firstNonEmpty(data['message'], errMap['message']);
      final next = _firstNonEmpty(data['nextStep'], data['next_step']);
      final action = data['action'];
      final actionType = action is Map ? _str(action['type']) : _str(action);
      return (
        code: code,
        title: _str(data['title']),
        message: message,
        nextStep: next.isNotEmpty ? next : null,
        action: actionType.isNotEmpty ? actionType : null,
        statusCode: status,
      );
    }
    return (
      code: '',
      title: '',
      message: 'Something went wrong. Please try again.',
      nextStep: null,
      action: null,
      statusCode: status,
    );
  }

  /// One-line message for a toast: `message`, falling back to `title`.
  String get display => message.isNotEmpty
      ? message
      : (title.isNotEmpty ? title : 'Something went wrong.');

  @override
  String toString() => 'ApiException($code, $message)';
}

String _str(dynamic v) => v == null ? '' : v.toString();

String _firstNonEmpty(dynamic a, dynamic b) {
  final sa = _str(a);
  if (sa.isNotEmpty && sa != 'null') return sa;
  final sb = _str(b);
  return (sb.isNotEmpty && sb != 'null') ? sb : '';
}
