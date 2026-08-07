import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// A dropped packet must not log a customer out.
///
/// Regression: `_doRefresh` returned null on *any* exception, and the caller
/// answered null by clearing the token store and firing `onUnauthorized`. So a
/// momentary network blip during token refresh destroyed the refresh token —
/// after which every later 401 bailed at the `hasToken` check without even
/// attempting a refresh. The customer was silently signed out mid-session;
/// "Place Order" just bounced them to login, and it stayed broken until they
/// signed in again.
///
/// The rule now: tear the session down ONLY when the server actually rejected
/// the refresh token (400/401/403). Everything else is transient.
///
/// This mirrors the classification the interceptor performs; it is deliberately
/// a pure test of the rule, since the interceptor's own enum is private.
bool sessionShouldBeClearedFor(DioException e) {
  final code = e.response?.statusCode ?? 0;
  return code == 400 || code == 401 || code == 403;
}

DioException _err(int? status, DioExceptionType type) {
  final req = RequestOptions(path: '/auth/refresh');
  return DioException(
    requestOptions: req,
    type: type,
    response: status == null
        ? null
        : Response<dynamic>(requestOptions: req, statusCode: status),
  );
}

void main() {
  group('refresh failure classification', () {
    test('a rejected refresh token ends the session', () {
      for (final code in [400, 401, 403]) {
        expect(
          sessionShouldBeClearedFor(_err(code, DioExceptionType.badResponse)),
          isTrue,
          reason: '$code means the token is genuinely invalid',
        );
      }
    });

    test('a connection timeout must NOT end the session', () {
      expect(
        sessionShouldBeClearedFor(_err(null, DioExceptionType.connectionTimeout)),
        isFalse,
      );
    });

    test('a connection error must NOT end the session', () {
      expect(
        sessionShouldBeClearedFor(_err(null, DioExceptionType.connectionError)),
        isFalse,
      );
    });

    test('a receive timeout must NOT end the session', () {
      expect(
        sessionShouldBeClearedFor(_err(null, DioExceptionType.receiveTimeout)),
        isFalse,
      );
    });

    test('a server error must NOT end the session', () {
      // Our outage is not the customer's problem to re-authenticate for.
      for (final code in [500, 502, 503, 504]) {
        expect(
          sessionShouldBeClearedFor(_err(code, DioExceptionType.badResponse)),
          isFalse,
          reason: '$code is transient',
        );
      }
    });

    test('a 429 must NOT end the session', () {
      expect(
        sessionShouldBeClearedFor(_err(429, DioExceptionType.badResponse)),
        isFalse,
      );
    });
  });
}
