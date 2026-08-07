import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/app/config/app_config.dart';
import 'package:user_app/core/network/api_client.dart';
import 'package:user_app/core/storage/secure_storage.dart';
import 'package:user_app/core/storage/token_storage.dart';
import 'package:user_app/features/catalog/data/datasources/backend_catalog_data_source.dart';

/// Returns one canned JSON body for every request — enough to exercise the
/// product mapper without a real backend.
class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.body);
  final Map<String, dynamic> body;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? _,
      Future<void>? __) async {
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  // Deterministic origin: prod base → https://api.thevsmart.com.
  setUpAll(() => AppConfig.init(flavor: AppFlavor.prod));

  BackendCatalogDataSource sourceReturning(Map<String, dynamic> data) {
    final dio = Dio()..httpClientAdapter = _CannedAdapter({'data': data});
    // getProductById uses the no-auth path, so secure storage is never read.
    final client = ApiClient(
      tokenStorage: TokenStorage(SecureStorage(const FlutterSecureStorage())),
      dio: dio,
    );
    return BackendCatalogDataSource(client);
  }

  test('relative media paths are resolved to absolute URLs', () async {
    final p = await sourceReturning({
      'id': '1',
      'name': 'Aashirvaad Atta 5kg',
      'price': 245,
      'mrp': 280,
      'imageUrl': '/api/v1/media/public/demo-atta/large',
      'images': [
        '/api/v1/media/public/demo-atta/large',
        'https://cdn.example.com/already-absolute.webp',
      ],
      'variants': const [],
    }).getProductById('1');

    expect(p.imageUrl, 'https://api.thevsmart.com/api/v1/media/public/demo-atta/large');
    expect(p.images.first, startsWith('https://api.thevsmart.com/'));
    // An already-absolute URL must be left untouched.
    expect(p.images[1], 'https://cdn.example.com/already-absolute.webp');
  });

  test('variant price / mrp / imageUrl / available are parsed (not dropped)', () async {
    final p = await sourceReturning({
      'id': '1',
      'name': 'Oil',
      'price': 100,
      'mrp': 120,
      'variants': [
        {
          'id': '2',
          'label': '10 kg',
          'priceDelta': 230,
          'price': 475,
          'mrp': 540,
          'imageUrl': '/api/v1/media/public/pack-10kg/medium',
          'available': 15,
          'inStock': true,
        },
      ],
    }).getProductById('1');

    expect(p.variants, hasLength(1));
    final v = p.variants.first;
    expect(v.price, 475);
    expect(v.mrp, 540);
    expect(v.available, 15);
    expect(v.imageUrl, 'https://api.thevsmart.com/api/v1/media/public/pack-10kg/medium');
    expect(v.isSellable, isTrue); // gated on available (15 > 0), not just inStock
  });
}
