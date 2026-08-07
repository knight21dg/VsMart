import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/core/network/api_client.dart';
import 'package:user_app/features/cart/domain/entities/cart_item.dart';
import 'package:user_app/features/orders/data/datasources/order_remote_datasource.dart';
import 'package:user_app/features/orders/domain/entities/order_enums.dart';

/// Records every request so a test can assert the exact call sequence checkout
/// makes, and returns canned envelopes so the mapping still runs.
class _RecordingApiClient implements ApiClient {
  final List<({String method, String path, Object? data})> calls = [];

  Iterable<({String method, String path, Object? data})> to(String path) =>
      calls.where((c) => c.path == path);

  Response<T> _ok<T>(String path, Object? body) =>
      Response<T>(requestOptions: RequestOptions(path: path), data: body as T);

  @override
  Future<Response<T>> put<T>(String path,
      {Object? data, Map<String, dynamic>? query, Options? options}) async {
    calls.add((method: 'PUT', path: path, data: data));
    return _ok<T>(path, {
      'data': {'items': <dynamic>[], 'bill': <String, dynamic>{}},
    });
  }

  @override
  Future<Response<T>> post<T>(String path,
      {Object? data,
      Map<String, dynamic>? query,
      Options? options,
      CancelToken? cancelToken}) async {
    calls.add((method: 'POST', path: path, data: data));
    return _ok<T>(path, {
      'data': {'id': '1', 'code': 'VS1', 'status': 'placed', 'total': 200},
    });
  }

  @override
  Future<Response<T>> delete<T>(String path,
      {Object? data, Map<String, dynamic>? query, Options? options}) async {
    calls.add((method: 'DELETE', path: path, data: data));
    return _ok<T>(path, {'data': <String, dynamic>{}});
  }

  @override
  Future<Response<T>> get<T>(String path,
      {Map<String, dynamic>? query,
      Options? options,
      CancelToken? cancelToken}) async {
    calls.add((method: 'GET', path: path, data: null));
    return _ok<T>(path, {
      'data': {'items': <dynamic>[], 'bill': <String, dynamic>{}},
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('_RecordingApiClient: unexpected ${invocation.memberName}');
}

const _rice = CartItem(
    productId: '10', name: 'Rice', brand: 'VS', unit: '1kg',
    price: 100, mrp: 120, quantity: 2);
const _dal = CartItem(
    productId: '11', name: 'Dal', brand: 'VS', unit: '1kg',
    price: 80, mrp: 90, quantity: 3, variantId: '55');

Future<void> _checkout(OrderRemoteDataSource ds, List<CartItem> items) =>
    ds.checkout(
      items: items,
      addressId: 'a1',
      method: PaymentMethod.cashOnDelivery,
      idempotencyKey: 'key-1',
    );

void main() {
  group('OrderRemoteDataSource cart sync', () {
    late _RecordingApiClient api;
    late OrderRemoteDataSource ds;

    setUp(() {
      api = _RecordingApiClient();
      ds = OrderRemoteDataSource(api);
    });

    test('syncs the whole cart with ONE atomic PUT /cart', () async {
      await _checkout(ds, [_rice, _dal]);

      final puts = api.to('/cart').toList();
      expect(puts, hasLength(1));
      expect(puts.single.method, 'PUT');
    });

    test('never issues per-line /cart/items writes', () async {
      // The regression guard. The old sync DELETEd every server line then POSTed
      // each item back against an ACCUMULATING endpoint — a failure partway
      // through left a partial cart and the retry doubled quantities.
      await _checkout(ds, [_rice, _dal]);

      final perLine =
          api.calls.where((c) => c.path.startsWith('/cart/items')).toList();
      expect(perLine, isEmpty);
    });

    test('sends absolute quantities and scopes the variant to its product',
        () async {
      await _checkout(ds, [_rice, _dal]);

      final body = api.to('/cart').single.data! as Map<String, dynamic>;
      expect(body['items'], [
        {'product_id': '10', 'quantity': 2},
        {'product_id': '11', 'quantity': 3, 'variant_id': '55'},
      ]);
    });

    test('an empty cart still PUTs, so the server cart is cleared not stale',
        () async {
      await _checkout(ds, const []);

      final body = api.to('/cart').single.data! as Map<String, dynamic>;
      expect(body['items'], isEmpty);
    });

    test('replaying checkout re-sends identical bodies (idempotent)', () async {
      await _checkout(ds, [_rice]);
      await _checkout(ds, [_rice]);

      final puts = api.to('/cart').toList();
      expect(puts, hasLength(2));
      // Same payload both times: absolute quantities, so the server converges on
      // qty 2 instead of climbing to 4.
      expect(puts.first.data, puts.last.data);
    });

    test('the cart PUT precedes the checkout POST', () async {
      await _checkout(ds, [_rice]);

      final order =
          api.calls.map((c) => '${c.method} ${c.path}').toList();
      expect(order.indexOf('PUT /cart'),
          lessThan(order.indexOf('POST /checkout')));
    });
  });
}
