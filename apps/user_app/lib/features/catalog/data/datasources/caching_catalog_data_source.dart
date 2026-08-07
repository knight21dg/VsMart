import '../../../../app/constants/storage_keys.dart';
import '../../../../core/network/pagination.dart';
import '../../../../core/storage/commerce_cache_manager.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/search_suggestions.dart';
import '../models/category_model.dart';
import '../models/product_model.dart';
import 'catalog_data_source.dart';

/// Stale-while-revalidate wrapper around a [CatalogDataSource]. Fresh cache
/// (within TTL) is returned instantly; otherwise the remote source is queried
/// and written through to cache, falling back to stale cache when the remote
/// fails (offline support). `search` is intentionally not cached.
class CachingCatalogDataSource implements CatalogDataSource {
  CachingCatalogDataSource({
    required this.remote,
    required this.cache,
    this.scope = 'global',
  });

  final CatalogDataSource remote;
  final CommerceCacheManager cache;

  /// Identifies the SERVING STORE this cache belongs to.
  ///
  /// The catalog is store-scoped: the backend returns only the products of the
  /// store serving the customer's location. Cache keys used to ignore that, so
  /// after changing location the app kept serving the PREVIOUS store's products
  /// out of Hive for the whole TTL — and indefinitely while offline. Every key
  /// is now namespaced by this, so a location change reads a different cache
  /// entry (a miss) and refetches, and going back is still instant.
  final String scope;

  static const _ttl = Duration(minutes: 5);

  /// Namespaces a cache key to the current serving store.
  String _k(String key) => '$scope::$key';

  Future<List<T>> _swrList<T>({
    required String box,
    required String key,
    required Future<List<T>> Function() fetch,
    required Map<String, dynamic> Function(T) toJson,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    if (cache.isFresh(box, key, _ttl)) {
      final cached = cache.readList(box, key);
      if (cached != null) return cached.map(fromJson).toList();
    }
    try {
      final fresh = await fetch();
      await cache.writeList(box, key, fresh.map(toJson).toList());
      return fresh;
    } catch (_) {
      final cached = cache.readList(box, key);
      if (cached != null) return cached.map(fromJson).toList();
      rethrow;
    }
  }

  @override
  Future<List<Category>> getDepartments() => _swrList(
        box: StorageKeys.categoryBox,
        key: _k('departments'),
        fetch: remote.getDepartments,
        toJson: CategoryModel.toJson,
        fromJson: CategoryModel.fromJson,
      );

  @override
  Future<List<Category>> getCategories({String? parentId}) => _swrList(
        box: StorageKeys.subCategoryBox,
        key: _k('categories_${parentId ?? 'all'}'),
        fetch: () => remote.getCategories(parentId: parentId),
        toJson: CategoryModel.toJson,
        fromJson: CategoryModel.fromJson,
      );

  // The store tree is cached per level, keyed by the parent, so drilling back up
  // is instant and the tab still renders offline.
  @override
  Future<List<Category>> getStoreCategories({String? parentId}) => _swrList(
        box: StorageKeys.subCategoryBox,
        key: _k('store_categories_${parentId ?? 'root'}'),
        fetch: () => remote.getStoreCategories(parentId: parentId),
        toJson: CategoryModel.toJson,
        fromJson: CategoryModel.fromJson,
      );

  @override
  Future<List<Product>> getStoreProducts({required String categoryId}) =>
      _swrList(
        box: StorageKeys.productBox,
        key: _k('store_products_$categoryId'),
        fetch: () => remote.getStoreProducts(categoryId: categoryId),
        toJson: ProductModel.toJson,
        fromJson: ProductModel.fromJson,
      );

  @override
  Future<List<Product>> getProducts({String? categoryId}) => _swrList(
        box: StorageKeys.productBox,
        key: _k('products_${categoryId ?? 'all'}'),
        fetch: () => remote.getProducts(categoryId: categoryId),
        toJson: ProductModel.toJson,
        fromJson: ProductModel.fromJson,
      );

  @override
  Future<List<Product>> getRecommended() => _swrList(
        box: StorageKeys.productBox,
        key: _k('recommended'),
        fetch: remote.getRecommended,
        toJson: ProductModel.toJson,
        fromJson: ProductModel.fromJson,
      );

  @override
  Future<List<Product>> getFeatured() => _swrList(
        box: StorageKeys.productBox,
        key: _k('featured'),
        fetch: remote.getFeatured,
        toJson: ProductModel.toJson,
        fromJson: ProductModel.fromJson,
      );

  @override
  Future<List<Product>> getPopular() => _swrList(
        box: StorageKeys.productBox,
        key: _k('popular'),
        fetch: remote.getPopular,
        toJson: ProductModel.toJson,
        fromJson: ProductModel.fromJson,
      );

  // Listing pages reflect live infinite scroll — served straight from the remote
  // (like search), not the stale-while-revalidate list cache.
  @override
  Future<Paginated<Product>> getProductsPage({
    String? categoryId,
    String? query,
    required int page,
    int pageSize = 20,
  }) =>
      remote.getProductsPage(
        categoryId: categoryId,
        query: query,
        page: page,
        pageSize: pageSize,
      );

  @override
  Future<Product> getProductById(String id) async {
    final key = _k('product_$id');
    try {
      final fresh = await remote.getProductById(id);
      await cache
          .writeList(StorageKeys.productBox, key, [ProductModel.toJson(fresh)]);
      return fresh;
    } catch (_) {
      final cached = cache.readList(StorageKeys.productBox, key);
      if (cached != null && cached.isNotEmpty) {
        return ProductModel.fromJson(cached.first);
      }
      rethrow;
    }
  }

  @override
  Future<List<Product>> search(String query) => remote.search(query);

  // Autocomplete is intentionally uncached — it must reflect live typing and is
  // already cheap on the backend.
  @override
  Future<SearchSuggestions> suggest(String query) => remote.suggest(query);
}
