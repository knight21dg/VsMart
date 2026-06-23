import '../../../../app/constants/storage_keys.dart';
import '../../../../core/storage/commerce_cache_manager.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/product.dart';
import '../models/category_model.dart';
import '../models/product_model.dart';
import 'catalog_data_source.dart';

/// Stale-while-revalidate wrapper around a [CatalogDataSource]. Fresh cache
/// (within TTL) is returned instantly; otherwise the remote source is queried
/// and written through to cache, falling back to stale cache when the remote
/// fails (offline support). `search` is intentionally not cached.
class CachingCatalogDataSource implements CatalogDataSource {
  CachingCatalogDataSource({required this.remote, required this.cache});

  final CatalogDataSource remote;
  final CommerceCacheManager cache;

  static const _ttl = Duration(minutes: 5);

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
        key: 'departments',
        fetch: remote.getDepartments,
        toJson: CategoryModel.toJson,
        fromJson: CategoryModel.fromJson,
      );

  @override
  Future<List<Category>> getCategories({String? parentId}) => _swrList(
        box: StorageKeys.subCategoryBox,
        key: 'categories_${parentId ?? 'all'}',
        fetch: () => remote.getCategories(parentId: parentId),
        toJson: CategoryModel.toJson,
        fromJson: CategoryModel.fromJson,
      );

  @override
  Future<List<Product>> getProducts({String? categoryId}) => _swrList(
        box: StorageKeys.productBox,
        key: 'products_${categoryId ?? 'all'}',
        fetch: () => remote.getProducts(categoryId: categoryId),
        toJson: ProductModel.toJson,
        fromJson: ProductModel.fromJson,
      );

  @override
  Future<List<Product>> getRecommended() => _swrList(
        box: StorageKeys.productBox,
        key: 'recommended',
        fetch: remote.getRecommended,
        toJson: ProductModel.toJson,
        fromJson: ProductModel.fromJson,
      );

  @override
  Future<List<Product>> getFeatured() => _swrList(
        box: StorageKeys.productBox,
        key: 'featured',
        fetch: remote.getFeatured,
        toJson: ProductModel.toJson,
        fromJson: ProductModel.fromJson,
      );

  @override
  Future<Product> getProductById(String id) async {
    final key = 'product_$id';
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
}
