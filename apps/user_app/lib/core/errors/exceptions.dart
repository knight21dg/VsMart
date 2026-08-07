/// Low-level exceptions thrown by data sources. These are caught in the
/// repository layer and mapped to [Failure]s for the domain/presentation layers.
library;

class AppException implements Exception {
  const AppException(this.message, {this.statusCode, this.data});

  final String message;
  final int? statusCode;
  final dynamic data;

  @override
  String toString() => '$runtimeType(statusCode: $statusCode, message: $message)';
}

/// Server returned a non-2xx response.
class ServerException extends AppException {
  const ServerException(super.message, {super.statusCode, super.data});
}

/// Network connectivity / timeout problems.
class NetworkException extends AppException {
  const NetworkException([super.message = 'No internet connection']);
}

class TimeoutException extends AppException {
  const TimeoutException([super.message = 'Request timed out']);
}

/// 401 / 403 — authentication or authorization failure.
class UnauthorizedException extends AppException {
  const UnauthorizedException([super.message = 'Session expired'])
      : super();
}

/// 422 / 400 — request validation failed. [errors] maps field -> messages.
class ValidationException extends AppException {
  const ValidationException(super.message, {this.errors, super.statusCode});

  final Map<String, List<String>>? errors;
}

/// Local cache / Hive read-write failure.
class CacheException extends AppException {
  const CacheException([super.message = 'Cache error']);
}

/// Secure storage failure.
class StorageException extends AppException {
  const StorageException([super.message = 'Storage error']);
}
