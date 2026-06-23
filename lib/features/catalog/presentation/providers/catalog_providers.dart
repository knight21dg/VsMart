import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../serviceability/presentation/providers/serviceability_providers.dart';
import '../../data/datasources/backend_catalog_data_source.dart';
import '../../data/datasources/caching_catalog_data_source.dart';
import '../../data/datasources/catalog_data_source.dart';
import '../../data/repositories/catalog_repository_impl.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/catalog_repository.dart';

/// Unwraps an `Either<Failure, T>` for use inside a [FutureProvider]: throws the
/// [Failure] (captured as `AsyncValue.error`) or returns the value.
T _unwrap<T>(Either<Failure, T> either) =>
    either.fold((f) => throw f, (value) => value);

/// ---------------------------------------------------------------------------
/// Wiring
/// ---------------------------------------------------------------------------
/// The underlying source of catalog data — the VS Mart backend (`/api/v1`).
/// The caching wrapper below adds offline support.
final catalogRemoteDataSourceProvider = Provider<CatalogDataSource>(
  (ref) {
    // Scope the catalog to the customer's serviceable store when one is resolved.
    // Harmless until the backend `zone_store_visibility` flag is enabled.
    final svc = ref.watch(currentServiceabilityProvider);
    final storeId = svc.serviceable ? svc.storeId : null;
    return BackendCatalogDataSource(ref.watch(apiClientProvider), storeId: storeId);
  },
);

/// Stale-while-revalidate caching source used by the repository.
final catalogDataSourceProvider = Provider<CatalogDataSource>(
  (ref) => CachingCatalogDataSource(
    remote: ref.watch(catalogRemoteDataSourceProvider),
    cache: ref.watch(commerceCacheManagerProvider),
  ),
);

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepositoryImpl(
    dataSource: ref.watch(catalogDataSourceProvider),
    networkInfo: ref.watch(networkInfoProvider),
  ),
);

/// ---------------------------------------------------------------------------
/// Read models
/// ---------------------------------------------------------------------------
final departmentsProvider = FutureProvider<List<Category>>(
  (ref) async => _unwrap(await ref.watch(catalogRepositoryProvider).getDepartments()),
);

final categoriesProvider =
    FutureProvider.family<List<Category>, String?>((ref, parentId) async =>
        _unwrap(await ref
            .watch(catalogRepositoryProvider)
            .getCategories(parentId: parentId)));

/// Sub-categories of a department — an intent-revealing alias over
/// [categoriesProvider] (sub-categories are categories scoped by `parentId`).
final subCategoriesProvider = categoriesProvider;

final productsProvider =
    FutureProvider.family<List<Product>, String?>((ref, categoryId) async =>
        _unwrap(await ref
            .watch(catalogRepositoryProvider)
            .getProducts(categoryId: categoryId)));

final productByIdProvider = FutureProvider.family<Product, String>(
  (ref, id) async =>
      _unwrap(await ref.watch(catalogRepositoryProvider).getProductById(id)),
);

final recommendedProductsProvider = FutureProvider<List<Product>>(
  (ref) async =>
      _unwrap(await ref.watch(catalogRepositoryProvider).getRecommended()),
);

final featuredProductsProvider = FutureProvider<List<Product>>(
  (ref) async =>
      _unwrap(await ref.watch(catalogRepositoryProvider).getFeatured()),
);

/// Popular products — derived by review count from the full catalog.
final popularProductsProvider = FutureProvider<List<Product>>((ref) async {
  final all = await ref.watch(productsProvider(null).future);
  final sorted = [...all]..sort((a, b) => b.reviews.compareTo(a.reviews));
  return sorted.take(6).toList();
});

final searchProductsProvider = FutureProvider.family<List<Product>, String>(
  (ref, query) async =>
      _unwrap(await ref.watch(catalogRepositoryProvider).search(query)),
);
