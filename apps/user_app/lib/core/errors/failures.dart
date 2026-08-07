import 'package:equatable/equatable.dart';

/// Domain-level error type. Repositories return `Either<Failure, T>` so the
/// presentation layer can handle errors without try/catch.
///
/// Beyond the human [message], a Failure can carry the backend's "actionable"
/// error envelope (camelCase wire contract): a stable machine [code], a [title],
/// an optional UI [actionType]/[actionTarget], plus [retryable]/[severity]/
/// [nextStep]. These are additive and default to safe no-ops, so existing
/// constructors keep working. The central presenter
/// (`app_error_presenter.dart`) reads them to drive navigation/dialogs.
sealed class Failure extends Equatable {
  const Failure(
    this.message, {
    this.statusCode,
    this.code,
    this.title,
    this.actionType,
    this.actionTarget,
    this.retryable = false,
    this.severity,
    this.nextStep,
  });

  final String message;
  final int? statusCode;

  /// Stable machine code from the envelope (e.g. `KYC_REQUIRED`). Null when the
  /// error did not come from an enveloped HTTP response.
  final String? code;

  /// Short headline for the error (e.g. "Verification Required").
  final String? title;

  /// Envelope `action.type`: one of `navigate`, `retry`, `retry_verification`,
  /// `logout`, `contact_support`, `refresh`, or null.
  final String? actionType;

  /// Envelope `action.target` route string (only for `navigate`), e.g.
  /// `/verification`.
  final String? actionTarget;

  /// Whether the operation is safe to retry.
  final bool retryable;

  /// `info` | `warning` | `error` | `critical`. Drives presentation weight.
  final String? severity;

  /// Optional guidance on what the user should do next.
  final String? nextStep;

  /// True when this Failure carries a machine [code] from the backend envelope
  /// and is therefore worth routing through the actionable presenter.
  bool get isActionable => code != null && code!.isNotEmpty;

  @override
  List<Object?> get props => [
        message,
        statusCode,
        code,
        title,
        actionType,
        actionTarget,
        retryable,
        severity,
        nextStep,
      ];
}

class ServerFailure extends Failure {
  const ServerFailure(
    super.message, {
    super.statusCode,
    super.code,
    super.title,
    super.actionType,
    super.actionTarget,
    super.retryable,
    super.severity,
    super.nextStep,
  });
}

class NetworkFailure extends Failure {
  const NetworkFailure([super.message = 'No internet connection']);
}

class TimeoutFailure extends Failure {
  const TimeoutFailure([super.message = 'Request timed out']);
}

class AuthFailure extends Failure {
  const AuthFailure([
    super.message = 'Authentication failed',
    int? statusCode,
  ]) : super(statusCode: statusCode);

  /// Construct from a backend envelope, carrying the actionable fields (used for
  /// e.g. `logout` / `retry_verification` actions on 401/403).
  const AuthFailure.actionable(
    super.message, {
    super.statusCode,
    super.code,
    super.title,
    super.actionType,
    super.actionTarget,
    super.retryable,
    super.severity,
    super.nextStep,
  });
}

class ValidationFailure extends Failure {
  const ValidationFailure(
    super.message, {
    this.errors,
    super.statusCode,
    super.code,
    super.title,
    super.actionType,
    super.actionTarget,
    super.retryable,
    super.severity,
    super.nextStep,
  });

  final Map<String, List<String>>? errors;

  @override
  List<Object?> get props => [...super.props, errors];
}

class CacheFailure extends Failure {
  const CacheFailure([super.message = 'Cache error']);
}

class UnknownFailure extends Failure {
  const UnknownFailure([super.message = 'Something went wrong']);
}

/// A failure built directly from the backend "actionable" error envelope when
/// the status code does not map to one of the more specific subtypes. Always
/// carries a machine [code] and the action/severity fields.
class AppFailure extends Failure {
  const AppFailure(
    super.message, {
    super.statusCode,
    super.code,
    super.title,
    super.actionType,
    super.actionTarget,
    super.retryable,
    super.severity,
    super.nextStep,
  });
}
