import '../../domain/entities/category.dart';
import '../../domain/entities/product.dart';

/// Data-source contract for the catalog. Implemented by [BackendCatalogDataSource]
/// (the `/api/v1` catalog API) and wrapped by a caching source in the providers.
abstract interface class CatalogDataSource {
  Future<List<Category>> getDepartments();
  Future<List<Category>> getCategories({String? parentId});
  Future<List<Product>> getProducts({String? categoryId});
  Future<Product> getProductById(String id);
  Future<List<Product>> getRecommended();
  Future<List<Product>> getFeatured();
  Future<List<Product>> search(String query);
}
