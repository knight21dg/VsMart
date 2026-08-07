import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import 'api_exception.dart';

/// What went wrong, in terms an agent standing at a gate can act on.
///
/// Before this, every non-[ApiException] collapsed to "Something went wrong.
/// Please try again." — so a dead mobile signal, a server outage and a genuine
/// rejection were indistinguishable. Agents work in basements, lifts and
/// villages with one bar; "no internet" has to say so, because the action they
/// take next is different (move and retry vs. call the store).
enum FailureKind {
  /// No usable connection — DNS/socket failure, or a request that never got out.
  offline,

  /// Reached the server but it took too long to answer.
  timeout,

  /// The server answered with 5xx.
  server,

  /// The backend rejected the request with an actionable envelope.
  api,

  /// Anything else.
  unknown,
}

/// A classified failure with a message that is safe to show as-is.
class Failure {
  const Failure(this.kind, this.message, {this.nextStep});

  final FailureKind kind;
  final String message;
  final String? nextStep;

  bool get isOffline => kind == FailureKind.offline || kind == FailureKind.timeout;

  /// Message plus the backend's next step, when there is one.
  String get display =>
      (nextStep != null && nextStep!.isNotEmpty) ? '$message\n$nextStep' : message;
}

/// Classify anything thrown by a repository call.
///
/// [fallback] is used only for genuinely unrecognised errors — never for a
/// network problem, which always gets its own wording.
Failure describeFailure(Object error, {String? fallback}) {
  if (error is ApiException) {
    return Failure(FailureKind.api, error.display, nextStep: error.nextStep);
  }

  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionError:
        return const Failure(FailureKind.offline, _offlineMessage);
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const Failure(FailureKind.timeout, _timeoutMessage);
      case DioExceptionType.badCertificate:
        return const Failure(FailureKind.unknown,
            "Couldn't verify a secure connection. Check the device date and time.");
      case DioExceptionType.cancel:
        return const Failure(FailureKind.unknown, 'That request was cancelled.');
      case DioExceptionType.badResponse:
        final status = error.response?.statusCode ?? 0;
        if (status >= 500) return const Failure(FailureKind.server, _serverMessage);
        // A 4xx normally arrives as a response (validateStatus lets it through)
        // and becomes an ApiException — if one lands here, parse it the same way.
        final parsed = ApiException.fromResponse(error.response);
        return Failure(FailureKind.api, parsed.display, nextStep: parsed.nextStep);
      case DioExceptionType.unknown:
        if (error.error is SocketException) {
          return const Failure(FailureKind.offline, _offlineMessage);
        }
        if (error.error is TimeoutException) {
          return const Failure(FailureKind.timeout, _timeoutMessage);
        }
        return Failure(FailureKind.unknown, fallback ?? _genericMessage);
    }
  }

  if (error is SocketException) {
    return const Failure(FailureKind.offline, _offlineMessage);
  }
  if (error is TimeoutException) {
    return const Failure(FailureKind.timeout, _timeoutMessage);
  }

  return Failure(FailureKind.unknown, fallback ?? _genericMessage);
}

const _offlineMessage =
    "You're offline. Check your mobile data or Wi-Fi and try again.";
const _timeoutMessage =
    'The network is too slow to finish that. Move to better signal and try again.';
const _serverMessage =
    'VS Mart is having trouble right now. Try again in a moment.';
const _genericMessage = 'Something went wrong. Please try again.';
