import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/network/pagination.dart';
import '../entities/category.dart';
import '../entities/product.dart';
import '../entities/search_suggestions.dart';

/// Catalog read operations: departments, categories and products.
abstract interface class CatalogRepository {
  /// Top-level departments shown in the categories rail.
  Future<Either<Failure, List<Category>>> getDepartments();

  /// Sub-categories, optionally scoped to a parent department.
  Future<Either<Failure, List<Category>>> getCategories({String? parentId});

  /// Products, optionally scoped to a category.
  Future<Either<Failure, List<Product>>> getProducts({String? categoryId});

  /// One level of the serving store's PRIVATE category tree (null = top level).
  Future<Either<Failure, List<Category>>> getStoreCategories({String? parentId});

  /// The serving store's own products in a category — the store tree's leaf grid.
  Future<Either<Failure, List<Product>>> getStoreProducts({
    required String categoryId,
  });

  /// A single server page of a category listing (or search, when [query] is set).
  /// Backs the listing screen's real, on-demand infinite scroll.
  Future<Either<Failure, Paginated<Product>>> getProductsPage({
    String? categoryId,
    String? query,
    required int page,
    int pageSize,
  });

  /// A single product by id.
  Future<Either<Failure, Product>> getProductById(String id);

  /// Curated recommendations for the home feed.
  Future<Either<Failure, List<Product>>> getRecommended();

  /// Featured / promoted products (e.g. best discounts).
  Future<Either<Failure, List<Product>>> getFeatured();

  /// Most-popular products for the home rail.
  Future<Either<Failure, List<Product>>> getPopular();

  /// Full-text product search.
  Future<Either<Failure, List<Product>>> search(String query);

  /// Lightweight as-you-type autocomplete (products + terms + categories).
  Future<Either<Failure, SearchSuggestions>> suggest(String query);
}
