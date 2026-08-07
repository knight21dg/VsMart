import '../../../../core/network/pagination.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/search_suggestions.dart';

/// Data-source contract for the catalog. Implemented by [BackendCatalogDataSource]
/// (the `/api/v1` catalog API) and wrapped by a caching source in the providers.
abstract interface class CatalogDataSource {
  Future<List<Category>> getDepartments();
  Future<List<Category>> getCategories({String? parentId});
  Future<List<Product>> getProducts({String? categoryId});

  /// One level of the serving store's PRIVATE category tree ([parentId] null =
  /// the top level). Only categories holding that store's own products appear,
  /// each flagged [Category.hasChildren] so the browser knows whether tapping it
  /// drills deeper or opens products. Empty when no store serves the customer.
  Future<List<Category>> getStoreCategories({String? parentId});

  /// The serving store's own (private) products in [categoryId] — the leaf grid
  /// of the store tree. Never includes company-wide or other stores' products.
  Future<List<Product>> getStoreProducts({required String categoryId});

  /// A SINGLE server page of a category listing (or search, when [query] is set),
  /// with the server's pagination meta. Backs the listing's real infinite scroll.
  Future<Paginated<Product>> getProductsPage({
    String? categoryId,
    String? query,
    required int page,
    int pageSize,
  });

  Future<Product> getProductById(String id);
  Future<List<Product>> getRecommended();
  Future<List<Product>> getFeatured();

  /// Most-popular products for the home rail (bounded single page).
  Future<List<Product>> getPopular();

  Future<List<Product>> search(String query);

  /// Lightweight as-you-type autocomplete (products + terms + categories).
  Future<SearchSuggestions> suggest(String query);
}
