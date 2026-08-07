import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/core/network/pagination.dart';
import 'package:user_app/core/storage/commerce_cache_manager.dart';
import 'package:user_app/features/catalog/data/datasources/caching_catalog_data_source.dart';
import 'package:user_app/features/catalog/data/datasources/catalog_data_source.dart';
import 'package:user_app/features/catalog/domain/entities/category.dart';
import 'package:user_app/features/catalog/domain/entities/product.dart';
import 'package:user_app/features/catalog/domain/entities/search_suggestions.dart';

import '../../helpers/fake_hive_service.dart';

/// The catalog is store-scoped server-side; the cache must be too.
///
/// Regression for "when the location changes, products should come from that
/// store only": every cache key was global, so after moving to another store's
/// area the app kept serving the PREVIOUS store's products out of Hive for the
/// whole TTL — and indefinitely while offline.
void main() {
  late FakeHiveService hive;
  late CommerceCacheManager cache;

  setUp(() {
    hive = FakeHiveService();
    cache = CommerceCacheManager(hive);
  });

  CachingCatalogDataSource sourceFor(String scope, _FakeRemote remote) =>
      CachingCatalogDataSource(remote: remote, cache: cache, scope: scope);

  test('a different store does not read the previous store\'s cached products',
      () async {
    final storeA = _FakeRemote(['A Rice', 'A Dal']);
    final a = sourceFor('store:1', storeA);
    expect((await a.getProducts()).map((p) => p.name), ['A Rice', 'A Dal']);
    expect(storeA.calls, 1);

    // Same customer, new location → new serving store. Even though this is well
    // inside the 5-minute TTL, it must MISS and refetch.
    final storeB = _FakeRemote(['B Atta']);
    final b = sourceFor('store:2', storeB);
    expect((await b.getProducts()).map((p) => p.name), ['B Atta']);
    expect(storeB.calls, 1, reason: 'must hit the network for the new store');
  });

  test('returning to a known store still serves its cache instantly', () async {
    final storeA = _FakeRemote(['A Rice']);
    await sourceFor('store:1', storeA).getProducts();
    await sourceFor('store:2', _FakeRemote(['B Atta'])).getProducts();

    // Back to store 1: cached, so no second network call.
    final again = _FakeRemote(['SHOULD NOT BE USED']);
    final names = (await sourceFor('store:1', again).getProducts())
        .map((p) => p.name);
    expect(names, ['A Rice']);
    expect(again.calls, 0);
  });

  test('the offline fallback is also store-scoped', () async {
    await sourceFor('store:1', _FakeRemote(['A Rice'])).getProducts();

    // Store 2, network down. Falling back to store 1's cache would show the
    // customer products the serving store does not sell.
    final offline = _FakeRemote([], throws: true);
    await expectLater(
      sourceFor('store:2', offline).getProducts(),
      throwsA(isA<Exception>()),
    );
  });

  test('categories and the store tree are scoped too', () async {
    final a = _FakeRemote([], categories: ['A Grocery']);
    await sourceFor('store:1', a).getDepartments();

    final b = _FakeRemote([], categories: ['B Grocery']);
    final names = (await sourceFor('store:2', b).getDepartments())
        .map((c) => c.name);
    expect(names, ['B Grocery']);
    expect(b.calls, 1);
  });
}

class _FakeRemote implements CatalogDataSource {
  _FakeRemote(this.products, {this.categories = const [], this.throws = false});

  final List<String> products;
  final List<String> categories;
  final bool throws;
  int calls = 0;

  List<Product> get _products => products
      .map<Product>((n) => Product(
            id: n,
            name: n,
            brand: 'VS',
            unit: 'each',
            price: 10,
            mrp: 12,
            categoryId: 'c1',
          ))
      .toList();

  @override
  Future<List<Product>> getProducts({String? categoryId}) async {
    calls++;
    if (throws) throw Exception('offline');
    return _products;
  }

  @override
  Future<List<Category>> getDepartments() async {
    calls++;
    if (throws) throw Exception('offline');
    return categories
        .map<Category>((n) => Category(id: n, name: n, productCount: 0))
        .toList();
  }

  @override
  Future<List<Category>> getCategories({String? parentId}) => getDepartments();

  @override
  Future<List<Category>> getStoreCategories({String? parentId}) =>
      getDepartments();

  @override
  Future<List<Product>> getStoreProducts({required String categoryId}) =>
      getProducts();

  @override
  Future<List<Product>> getRecommended() => getProducts();

  @override
  Future<List<Product>> getFeatured() => getProducts();

  @override
  Future<List<Product>> getPopular() => getProducts();

  @override
  Future<Product> getProductById(String id) async => _products.first;

  @override
  Future<Paginated<Product>> getProductsPage({
    String? categoryId,
    String? query,
    required int page,
    int pageSize = 20,
  }) async =>
      Paginated<Product>(
        items: _products,
        meta: const PageMeta(
            currentPage: 1, lastPage: 1, perPage: 20, total: 0),
      );

  @override
  Future<List<Product>> search(String query) => getProducts();

  @override
  Future<SearchSuggestions> suggest(String query) async =>
      SearchSuggestions.empty;
}
