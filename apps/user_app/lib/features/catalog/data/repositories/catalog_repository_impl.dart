import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/network/base_repository.dart';
import '../../../../core/network/network_info.dart';
import '../../../../core/network/pagination.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/search_suggestions.dart';
import '../../domain/repositories/catalog_repository.dart';
import '../datasources/catalog_data_source.dart';

/// [CatalogRepository] backed by a [CatalogDataSource]. Errors are normalised to
/// [Failure] via [BaseRepository.guard]. Connectivity is not required: the
/// caching data source serves cached catalog data when offline.
class CatalogRepositoryImpl with BaseRepository implements CatalogRepository {
  CatalogRepositoryImpl({
    required this.dataSource,
    required this.networkInfo,
  });

  final CatalogDataSource dataSource;

  @override
  final NetworkInfo networkInfo;

  @override
  Future<Either<Failure, List<Category>>> getDepartments() =>
      guard(dataSource.getDepartments, requireConnection: false);

  @override
  Future<Either<Failure, List<Category>>> getCategories({String? parentId}) =>
      guard(() => dataSource.getCategories(parentId: parentId),
          requireConnection: false);

  @override
  Future<Either<Failure, List<Product>>> getProducts({String? categoryId}) =>
      guard(() => dataSource.getProducts(categoryId: categoryId),
          requireConnection: false);

  @override
  Future<Either<Failure, List<Category>>> getStoreCategories({
    String? parentId,
  }) =>
      guard(() => dataSource.getStoreCategories(parentId: parentId),
          requireConnection: false);

  @override
  Future<Either<Failure, List<Product>>> getStoreProducts({
    required String categoryId,
  }) =>
      guard(() => dataSource.getStoreProducts(categoryId: categoryId),
          requireConnection: false);

  @override
  Future<Either<Failure, Paginated<Product>>> getProductsPage({
    String? categoryId,
    String? query,
    required int page,
    int pageSize = 20,
  }) =>
      guard(
        () => dataSource.getProductsPage(
          categoryId: categoryId,
          query: query,
          page: page,
          pageSize: pageSize,
        ),
        requireConnection: false,
      );

  @override
  Future<Either<Failure, Product>> getProductById(String id) =>
      guard(() => dataSource.getProductById(id), requireConnection: false);

  @override
  Future<Either<Failure, List<Product>>> getRecommended() =>
      guard(dataSource.getRecommended, requireConnection: false);

  @override
  Future<Either<Failure, List<Product>>> getFeatured() =>
      guard(dataSource.getFeatured, requireConnection: false);

  @override
  Future<Either<Failure, List<Product>>> getPopular() =>
      guard(dataSource.getPopular, requireConnection: false);

  @override
  Future<Either<Failure, List<Product>>> search(String query) =>
      guard(() => dataSource.search(query), requireConnection: false);

  @override
  Future<Either<Failure, SearchSuggestions>> suggest(String query) =>
      guard(() => dataSource.suggest(query), requireConnection: false);
}
