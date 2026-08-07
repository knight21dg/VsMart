import 'package:dartz/dartz.dart';
import 'package:user_app/core/errors/failures.dart';
import 'package:user_app/features/catalog/domain/entities/product.dart';
import 'package:user_app/features/catalog/domain/repositories/catalog_repository.dart';

/// Serves a fixed set of products by id; everything else routes to noSuchMethod.
class FakeCatalogRepository implements CatalogRepository {
  FakeCatalogRepository(this._products);

  final Map<String, Product> _products;

  @override
  Future<Either<Failure, Product>> getProductById(String id) async {
    final p = _products[id];
    return p == null
        ? const Left(ServerFailure('not found'))
        : Right(p);
  }

  @override
  Future<Either<Failure, List<Product>>> getProducts({String? categoryId}) async =>
      Right(_products.values.toList());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
