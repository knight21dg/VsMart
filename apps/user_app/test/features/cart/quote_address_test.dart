import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/core/network/api_client.dart';
import 'package:user_app/features/cart/data/datasources/cart_bill_data_source.dart';
import 'package:user_app/features/cart/domain/entities/cart.dart';
import 'package:user_app/features/cart/domain/entities/cart_item.dart';

/// Records the quote request so a test can assert what the bill was priced against.
class _RecordingApiClient implements ApiClient {
  Object? lastBody;

  @override
  Future<Response<T>> post<T>(String path,
      {Object? data,
      Map<String, dynamic>? query,
      Options? options,
      CancelToken? cancelToken}) async {
    lastBody = data;
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      data: {
        'data': {'bill': <String, dynamic>{}},
      } as T,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('_RecordingApiClient: unexpected ${invocation.memberName}');
}

const _cart = Cart([
  CartItem(
      productId: '10', name: 'Rice', brand: 'VS', unit: '1kg',
      price: 100, mrp: 120, quantity: 2),
]);

void main() {
  group('CartBillDataSource.quote', () {
    late _RecordingApiClient api;
    late CartBillDataSource ds;

    setUp(() {
      api = _RecordingApiClient();
      ds = CartBillDataSource(api);
    });

    Map<String, dynamic> body() => api.lastBody! as Map<String, dynamic>;

    test('sends the selected address so zone fee overrides are applied', () async {
      // Without this the preview priced at platform defaults while checkout
      // charged the zone rate — the total changed between cart and receipt.
      await ds.quote(_cart, addressId: 'addr-1');

      expect(body()['address_id'], 'addr-1');
    });

    test('omits address_id when no address is selected yet', () async {
      await ds.quote(_cart);

      expect(body().containsKey('address_id'), isFalse);
    });

    test('omits an empty address id rather than sending a blank one', () async {
      await ds.quote(_cart, addressId: '');

      expect(body().containsKey('address_id'), isFalse);
    });

    test('still sends the cart lines alongside the address', () async {
      await ds.quote(_cart, addressId: 'addr-1');

      expect(body()['items'], [
        {'product_id': '10', 'quantity': 2},
      ]);
    });
  });
}
