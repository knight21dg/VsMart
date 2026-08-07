import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/core/network/api_client.dart';
import 'package:user_app/features/address/data/datasources/address_remote_datasource.dart';
import 'package:user_app/features/address/domain/entities/address.dart';

/// Captures the body the datasource sends, so we can assert on the exact
/// payload that reaches the wire.
class _RecordingApiClient implements ApiClient {
  Object? lastBody;
  String? lastPath;

  Response<T> _ok<T>(String path) => Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'data': {
            'id': '1',
            'name': 'X',
            'phone': '9',
            'line1': 'L',
            'pincode': '533005',
          }
        } as T,
      );

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    lastPath = path;
    lastBody = data;
    return _ok<T>(path);
  }

  @override
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    lastPath = path;
    lastBody = data;
    return _ok<T>(path);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('_RecordingApiClient: unexpected call');
}

/// The address a customer creates after pinning a location: device GPS reports
/// 7+ decimal places.
const _pinned = Address(
  id: 'a1',
  name: 'Test User',
  phone: '9494429963',
  line1: '69-16-8, Vs Raju Nagar',
  area: 'Vs Raju Nagar',
  district: 'Kakinada',
  state: 'Andhra Pradesh',
  pincode: '533005',
  latitude: 16.9890751,
  longitude: 82.2474607,
);

void main() {
  group('address payload coordinates', () {
    // Regression: the backend stores DecimalField(decimal_places=6). Sending
    // raw 7dp GPS came back as HTTP 400 on BOTH coordinates, so an address with
    // a pinned location could never be saved — while the same address without
    // coordinates saved fine.
    test('create rounds coordinates to the 6dp the backend stores', () async {
      final client = _RecordingApiClient();
      await AddressRemoteDataSource(client).create(_pinned);

      final body = client.lastBody! as Map<String, dynamic>;
      expect(body['latitude'], 16.989075);
      expect(body['longitude'], 82.247461); // rounded half-up
    });

    test('edit rounds them too — the app PATCHes the whole body', () async {
      final client = _RecordingApiClient();
      await AddressRemoteDataSource(client).update(_pinned);

      final body = client.lastBody! as Map<String, dynamic>;
      expect(body['latitude'], 16.989075);
      expect(body['longitude'], 82.247461);
    });

    test('coordinates are omitted entirely when not set', () async {
      final client = _RecordingApiClient();
      await AddressRemoteDataSource(client).create(
        const Address(
          id: 'a2',
          name: 'No Pin',
          phone: '9494429963',
          line1: 'Somewhere',
          pincode: '533005',
        ),
      );

      final body = client.lastBody! as Map<String, dynamic>;
      expect(body.containsKey('latitude'), isFalse);
      expect(body.containsKey('longitude'), isFalse);
    });

    test('already-short coordinates pass through unchanged', () async {
      final client = _RecordingApiClient();
      await AddressRemoteDataSource(client).create(
        const Address(
          id: 'a3',
          name: 'Short',
          phone: '9494429963',
          line1: 'Somewhere',
          pincode: '533005',
          latitude: 16.98,
          longitude: 82.24,
        ),
      );

      final body = client.lastBody! as Map<String, dynamic>;
      expect(body['latitude'], 16.98);
      expect(body['longitude'], 82.24);
    });

    test('negative coordinates round correctly', () async {
      final client = _RecordingApiClient();
      await AddressRemoteDataSource(client).create(
        const Address(
          id: 'a4',
          name: 'West',
          phone: '9494429963',
          line1: 'Somewhere',
          pincode: '533005',
          latitude: -16.9890756,
          longitude: -82.2474604,
        ),
      );

      final body = client.lastBody! as Map<String, dynamic>;
      expect(body['latitude'], -16.989076);
      expect(body['longitude'], -82.24746);
    });

    test('line1 is sent under the exact key the backend requires', () async {
      // `line1` is required server-side; a mangled key here is a silent 400.
      final client = _RecordingApiClient();
      await AddressRemoteDataSource(client).create(_pinned);

      final body = client.lastBody! as Map<String, dynamic>;
      expect(body.containsKey('line1'), isTrue);
      expect(body['line1'], '69-16-8, Vs Raju Nagar');
    });
  });
}
