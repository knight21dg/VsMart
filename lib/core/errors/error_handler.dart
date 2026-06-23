import 'package:dio/dio.dart';

import 'exceptions.dart';
import 'failures.dart';

/// Translates raw errors (Dio, exceptions) into typed domain [Failure]s.
abstract final class ErrorHandler {
  ErrorHandler._();

  /// Map any caught error into a [Failure].
  static Failure handle(Object error) {
    if (error is Failure) return error;
    if (error is DioException) return _fromDio(error);
    if (error is AppException) return _fromAppException(error);
    return UnknownFailure(error.toString());
  }

  static Failure _fromAppException(AppException e) {
    return switch (e) {
      NetworkException() => NetworkFailure(e.message),
      TimeoutException() => TimeoutFailure(e.message),
      UnauthorizedException() => AuthFailure(e.message, e.statusCode),
      ValidationException() => ValidationFailure(
          e.message,
          errors: e.errors,
          statusCode: e.statusCode,
        ),
      CacheException() => CacheFailure(e.message),
      StorageException() => CacheFailure(e.message),
      ServerException() => ServerFailure(e.message, statusCode: e.statusCode),
      _ => UnknownFailure(e.message),
    };
  }

  static Failure _fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const TimeoutFailure();
      case DioExceptionType.connectionError:
        return const NetworkFailure();
      case DioExceptionType.cancel:
        return const UnknownFailure('Request cancelled');
      case DioExceptionType.badCertificate:
        return const NetworkFailure('Bad certificate');
      case DioExceptionType.badResponse:
        return _fromResponse(e.response);
      case DioExceptionType.unknown:
        return NetworkFailure(e.message ?? 'Network error');
    }
  }

  static Failure _fromResponse(Response<dynamic>? response) {
    final status = response?.statusCode ?? 0;
    final data = response?.data;
    final env = _Envelope.parse(data);

    // Prefer the envelope's top-level message; fall back to the legacy
    // message/detail/error extraction; finally a status-based default.
    final message =
        env?.message ?? _extractMessage(data) ?? _defaultMessage(status);

    if (status == 401 || status == 403) {
      return AuthFailure.actionable(
        message,
        statusCode: status,
        code: env?.code,
        title: env?.title,
        actionType: env?.actionType,
        actionTarget: env?.actionTarget,
        retryable: env?.retryable ?? false,
        severity: env?.severity,
        nextStep: env?.nextStep,
      );
    }
    if (status == 422 || status == 400) {
      return ValidationFailure(
        message,
        statusCode: status,
        errors: _extractFieldErrors(data),
        code: env?.code,
        title: env?.title,
        actionType: env?.actionType,
        actionTarget: env?.actionTarget,
        retryable: env?.retryable ?? false,
        severity: env?.severity,
        nextStep: env?.nextStep,
      );
    }
    // Enveloped error with a machine code on any other status -> AppFailure so
    // the presenter can act on it; otherwise the generic ServerFailure.
    if (env != null && env.code != null && env.code!.isNotEmpty) {
      return AppFailure(
        message,
        statusCode: status,
        code: env.code,
        title: env.title,
        actionType: env.actionType,
        actionTarget: env.actionTarget,
        retryable: env.retryable,
        severity: env.severity,
        nextStep: env.nextStep,
      );
    }
    return ServerFailure(message, statusCode: status);
  }

  static String? _extractMessage(dynamic data) {
    if (data is! Map) return null;
    // Backend error envelope: {error: {code, message, fields}}.
    final error = data['error'];
    if (error is Map && error['message'] is String &&
        (error['message'] as String).isNotEmpty) {
      return error['message'] as String;
    }
    // Flat shapes: {message}, {detail} (RFC 9457), or {error: "..."} as a string.
    for (final key in ['message', 'detail', 'error']) {
      final m = data[key];
      if (m is String && m.isNotEmpty) return m;
    }
    return null;
  }

  static Map<String, List<String>>? _extractFieldErrors(dynamic data) {
    if (data is! Map) return null;
    // Prefer the backend envelope's nested error.fields, then top-level errors.
    final error = data['error'];
    final raw = (error is Map && error['fields'] is Map)
        ? error['fields'] as Map
        : (data['errors'] is Map ? data['errors'] as Map : null);
    if (raw == null || raw.isEmpty) return null;
    return raw.map(
      (k, v) => MapEntry(
        k.toString(),
        (v is List) ? v.map((e) => e.toString()).toList() : [v.toString()],
      ),
    );
  }

  static String _defaultMessage(int status) {
    return switch (status) {
      400 => 'Bad request',
      404 => 'Not found',
      409 => 'Conflict',
      429 => 'Too many requests. Please slow down.',
      >= 500 => 'Server error. Please try again later.',
      _ => 'Something went wrong',
    };
  }
}

/// Parsed view of the backend "actionable" error envelope (camelCase wire
/// contract). Only recognised when the body is a JSON object that looks like
/// the envelope (carries `success`, `code`, or `action`); otherwise [parse]
/// returns null and the legacy extraction takes over.
class _Envelope {
  const _Envelope({
    this.code,
    this.title,
    this.message,
    this.actionType,
    this.actionTarget,
    this.retryable = false,
    this.severity,
    this.nextStep,
  });

  final String? code;
  final String? title;
  final String? message;
  final String? actionType;
  final String? actionTarget;
  final bool retryable;
  final String? severity;
  final String? nextStep;

  static _Envelope? parse(dynamic data) {
    if (data is! Map) return null;
    // Heuristic: only treat as an envelope when it carries one of the
    // distinguishing top-level keys. Avoids hijacking arbitrary JSON bodies.
    final looksEnveloped = data.containsKey('success') ||
        data.containsKey('code') ||
        data.containsKey('action');
    if (!looksEnveloped) return null;

    String? str(Object? v) =>
        (v is String && v.isNotEmpty) ? v : null;

    // action: { type, target } | null
    String? actionType;
    String? actionTarget;
    final action = data['action'];
    if (action is Map) {
      actionType = str(action['type']);
      actionTarget = str(action['target']);
    }

    // Top-level code/message, falling back to the nested back-compat `error`.
    final error = data['error'];
    final code = str(data['code']) ??
        (error is Map ? str(error['code']) : null);
    final message = str(data['message']) ??
        (error is Map ? str(error['message']) : null);

    return _Envelope(
      code: code,
      title: str(data['title']),
      message: message,
      actionType: actionType,
      actionTarget: actionTarget,
      retryable: data['retryable'] == true,
      severity: str(data['severity']),
      nextStep: str(data['nextStep']),
    );
  }
}
