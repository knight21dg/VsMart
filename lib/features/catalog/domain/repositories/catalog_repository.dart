import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/category.dart';
import '../entities/product.dart';

/// Catalog read operations: departments, categories and products.
abstract interface class CatalogRepository {
  /// Top-level departments shown in the categories rail.
  Future<Either<Failure, List<Category>>> getDepartments();

  /// Sub-categories, optionally scoped to a parent department.
  Future<Either<Failure, List<Category>>> getCategories({String? parentId});

  /// Products, optionally scoped to a category.
  Future<Either<Failure, List<Product>>> getProducts({String? categoryId});

  /// A single product by id.
  Future<Either<Failure, Product>> getProductById(String id);

  /// Curated recommendations for the home feed.
  Future<Either<Failure, List<Product>>> getRecommended();

  /// Featured / promoted products (e.g. best discounts).
  Future<Either<Failure, List<Product>>> getFeatured();

  /// Full-text product search.
  Future<Either<Failure, List<Product>>> search(String query);
}
