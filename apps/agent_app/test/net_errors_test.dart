// Every failure an agent can hit in the field has to be distinguishable.
//
// Before this classifier, anything that wasn't a backend envelope collapsed to
// "Something went wrong. Please try again." — so no signal, a slow network, a
// server outage and a genuine rejection all read identically, even though the
// agent's next move differs for each.
import 'dart:async';
import 'dart:io';

import 'package:agent_app/core/api_exception.dart';
import 'package:agent_app/core/net_errors.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

RequestOptions _req() => RequestOptions(path: '/deliveries/1/arrive');

void main() {
  group('describeFailure', () {
    test('connection error → offline, and says so', () {
      final f = describeFailure(
          DioException(requestOptions: _req(), type: DioExceptionType.connectionError));
      expect(f.kind, FailureKind.offline);
      expect(f.isOffline, isTrue);
      expect(f.message.toLowerCase(), contains('offline'));
    });

    test('a raw SocketException is offline too', () {
      final f = describeFailure(const SocketException('failed host lookup'));
      expect(f.kind, FailureKind.offline);
    });

    test('socket failure wrapped as DioExceptionType.unknown is offline', () {
      final f = describeFailure(DioException(
        requestOptions: _req(),
        type: DioExceptionType.unknown,
        error: const SocketException('no route to host'),
      ));
      expect(f.kind, FailureKind.offline);
    });

    for (final type in [
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
    ]) {
      test('$type → timeout, told apart from being offline', () {
        final f = describeFailure(DioException(requestOptions: _req(), type: type));
        expect(f.kind, FailureKind.timeout);
        expect(f.isOffline, isTrue); // both mean "network problem" to the UI
        expect(f.message, isNot(contains('offline')));
      });
    }

    test('TimeoutException (e.g. a GPS/HTTP future giving up) → timeout', () {
      expect(describeFailure(TimeoutException('slow')).kind, FailureKind.timeout);
    });

    test('5xx → server trouble, never a rejection message', () {
      final f = describeFailure(DioException(
        requestOptions: _req(),
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(requestOptions: _req(), statusCode: 502),
      ));
      expect(f.kind, FailureKind.server);
      expect(f.isOffline, isFalse);
    });

    test('backend envelope wins: message + nextStep are shown verbatim', () {
      final f = describeFailure(ApiException(
        code: 'DELIVERY_LOCATION_MISMATCH',
        title: 'Too far away',
        message: "You're 1.2 km from the delivery pin.",
        nextStep: 'Get within 100 m to confirm arrival.',
      ));
      expect(f.kind, FailureKind.api);
      expect(f.display, contains('1.2 km'));
      expect(f.display, contains('within 100 m'));
    });

    test('a 4xx that arrives as a DioException is still parsed as an envelope', () {
      final f = describeFailure(DioException(
        requestOptions: _req(),
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: _req(),
          statusCode: 409,
          data: {
            'success': false,
            'code': 'DELIVERY_LOCATION_MISMATCH',
            'message': 'Too far from the pin.',
          },
        ),
      ));
      expect(f.kind, FailureKind.api);
      expect(f.message, 'Too far from the pin.');
    });

    test('unrecognised errors use the caller fallback, network ones never do', () {
      expect(describeFailure(StateError('boom'), fallback: 'Could not load your cash.').message,
          'Could not load your cash.');
      // A network failure must keep its own wording even when a fallback exists.
      final offline = describeFailure(
          DioException(requestOptions: _req(), type: DioExceptionType.connectionError),
          fallback: 'Could not load your cash.');
      expect(offline.message, isNot('Could not load your cash.'));
    });

    test('display folds in nextStep only when there is one', () {
      const bare = Failure(FailureKind.api, 'Nope');
      expect(bare.display, 'Nope');
      const withNext = Failure(FailureKind.api, 'Nope', nextStep: 'Try later.');
      expect(withNext.display, 'Nope\nTry later.');
    });
  });
}
