// Renders the EXACT customer JSON `GET /api/v1/products/{id}` returns for a
// store-added product through the real mapper, and asserts every value the UI
// shows. Double quotes mirror the wire JSON on purpose.
// ignore_for_file: prefer_single_quotes
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
import 'package:user_app/features/catalog/domain/entities/product.dart';

const _apiDetailJson = {
  "id": "1",
  "name": "Aashirvaad Atta 5kg",
  "brand": "Aashirvaad",
  "unit": "5 kg",
  "price": 245.0,
  "mrp": 280.0,
  "creditPrice": null,
  "discountPercent": 12,
  "discountAmount": 35.0,
  "categoryId": "1",
  "rating": 0.0,
  "reviews": 0,
  "imageUrl": "/api/v1/media/public/demo-atta/large",
  "images": [
    "/api/v1/media/public/demo-atta/large",
    "/api/v1/media/public/demo-atta-2/large",
  ],
  "inStock": true,
  "stockCount": 55,
  "availableQuantity": 55,
  "description": "Whole wheat atta, stone-ground.",
  "specifications": {},
  "variants": [
    {"id": "1", "label": "5 kg", "priceDelta": 0.0, "price": 245.0, "mrp": 280.0,
     "imageUrl": "/api/v1/media/public/demo-atta/large", "available": 40, "inStock": true},
    {"id": "2", "label": "10 kg", "priceDelta": 230.0, "price": 475.0, "mrp": 540.0,
     "imageUrl": "/api/v1/media/public/demo-atta/large", "available": 15, "inStock": true},
  ],
};

class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.body);
  final Map<String, dynamic> body;
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? _, Future<void>? __) async =>
      ResponseBody.fromString(jsonEncode(body), 200,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(() => AppConfig.init(flavor: AppFlavor.prod));

  Future<Product> mapApiJson(Map<String, dynamic> json) {
    final dio = Dio()..httpClientAdapter = _CannedAdapter({'data': json});
    final client = ApiClient(
      tokenStorage: TokenStorage(SecureStorage(const FlutterSecureStorage())),
      dio: dio,
    );
    return BackendCatalogDataSource(client).getProductById('1');
  }

  const origin = 'https://api.thevsmart.com';

  test('renders the product API JSON exactly as the UI consumes it', () async {
    final p = await mapApiJson(Map<String, dynamic>.from(_apiDetailJson));

    // Images resolved to absolute (so they load, not a blank tile).
    expect(p.imageUrl, '$origin/api/v1/media/public/demo-atta/large');
    expect(p.gallery, hasLength(2));
    expect(p.gallery.every((u) => u.startsWith('$origin/')), isTrue);

    // Pricing + stock as the card shows them.
    expect(p.displayPrice, 245.0);
    expect(p.displayMrp, 280.0);
    expect(p.effectiveInStock, isTrue);
    // Discount is DERIVED from the displayed pack (variant-aware), not the API's
    // top-level discountPercent(12): 35/280 = 12.5% rounds half-up → 13.
    expect(p.discountPercent, 13);

    // Both packs carry their OWN price / mrp / stock / photo.
    expect(p.variants, hasLength(2));
    final tenKg = p.variants.firstWhere((x) => x.label == '10 kg');
    expect(tenKg.price, 475.0);
    expect(tenKg.mrp, 540.0);
    expect(tenKg.available, 15);
    expect(tenKg.isSellable, isTrue);
    expect(tenKg.imageUrl, startsWith('$origin/'));

    // Cheapest sellable pack drives the card price.
    expect(p.displayVariant?.label, '5 kg');
  });

  test('sold-out pack is not sellable; display pack skips it', () async {
    final json = Map<String, dynamic>.from(_apiDetailJson);
    json['variants'] = [
      {"id": "1", "label": "5 kg", "priceDelta": 0.0, "price": 245.0, "mrp": 280.0,
       "imageUrl": "", "available": 0, "inStock": false},
      {"id": "2", "label": "10 kg", "priceDelta": 230.0, "price": 475.0, "mrp": 540.0,
       "imageUrl": "", "available": 8, "inStock": true},
    ];
    final p = await mapApiJson(json);
    expect(p.variants.firstWhere((x) => x.label == '5 kg').isSellable, isFalse);
    expect(p.variants.firstWhere((x) => x.label == '10 kg').isSellable, isTrue);
    expect(p.displayVariant?.label, '10 kg');
    expect(p.effectiveInStock, isTrue);
  });
}
