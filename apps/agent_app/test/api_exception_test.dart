import 'package:agent_app/core/api_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

Response<dynamic> _res(dynamic data, int status) => Response<dynamic>(
      requestOptions: RequestOptions(path: '/x'),
      statusCode: status,
      data: data,
    );

void main() {
  group('ApiException.parse', () {
    test('reads the top-level actionable envelope and upper-cases the code', () {
      final e = ApiException.fromResponse(_res({
        'code': 'delivery_geofence_failed',
        'title': 'Too far',
        'message': 'You are not at the address.',
        'nextStep': 'Move closer and retry.',
        'action': {'type': 'retry'},
      }, 400));
      expect(e.code, 'DELIVERY_GEOFENCE_FAILED');
      expect(e.message, 'You are not at the address.');
      expect(e.nextStep, 'Move closer and retry.');
      expect(e.action, 'retry');
      expect(e.statusCode, 400);
      expect(e.display, 'You are not at the address.');
    });

    test('falls back to the nested error.{code,message}', () {
      final e = ApiException.fromResponse(_res({
        'error': {'code': 'otp_invalid', 'message': 'Bad code'},
      }, 400));
      expect(e.code, 'OTP_INVALID');
      expect(e.message, 'Bad code');
    });

    test('accepts snake_case next_step', () {
      final e = ApiException.fromResponse(
          _res({'message': 'x', 'next_step': 'do y'}, 400));
      expect(e.nextStep, 'do y');
    });

    test('non-map body yields a generic message + status', () {
      final e = ApiException.fromResponse(_res('oops', 500));
      expect(e.message, contains('went wrong'));
      expect(e.statusCode, 500);
      expect(e.code, '');
    });

    test('display falls back to title, then a generic line', () {
      expect(ApiException(code: '', title: 'T', message: '').display, 'T');
      expect(ApiException(code: '', title: '', message: '').display,
          'Something went wrong.');
    });

    test('null string "null" is treated as empty', () {
      final e = ApiException.fromResponse(
          _res({'code': 'null', 'message': 'real'}, 400));
      expect(e.code, '');
      expect(e.message, 'real');
    });
  });
}
