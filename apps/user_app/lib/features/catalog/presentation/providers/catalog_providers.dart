import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../../shared/providers/location_scope_provider.dart';
import '../../data/datasources/backend_catalog_data_source.dart';
import '../../data/datasources/caching_catalog_data_source.dart';
import '../../data/datasources/catalog_data_source.dart';
import '../../data/repositories/catalog_repository_impl.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/search_suggestions.dart';
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
    // Send the customer's LOCATION so the backend resolves the serving store
    // (zone → store) itself and returns only that store's catalog — the store is
    // never chosen by the client. The resolved store id is sent only as a
    // transitional fallback. Harmless until `zone_store_visibility` is enabled.
    //
    // Priority: a location the customer PICKED via change-location (manual
    // override), then the selected delivery ADDRESS, then the live device
    // (NEARBY) location — so a change-location pin-drop re-binds the serving store
    // to the new spot, and products still resolve to the nearby zone's store even
    // before the customer has saved an address.
    final scope = ref.watch(locationScopeProvider);
    return BackendCatalogDataSource(
      ref.watch(apiClientProvider),
      lat: scope.lat,
      lng: scope.lng,
      pincode: scope.pincode,
      storeId: scope.storeId,
    );
  },
);

/// Stale-while-revalidate caching source used by the repository.
///
/// The cache is namespaced by the serving store ([LocationScope.cacheKey]): the
/// catalog is store-scoped server-side, but the keys weren't — so after a location
/// change the app kept serving the PREVIOUS store's products out of Hive for the
/// whole TTL, and forever while offline.
final catalogDataSourceProvider = Provider<CatalogDataSource>(
  (ref) => CachingCatalogDataSource(
    remote: ref.watch(catalogRemoteDataSourceProvider),
    cache: ref.watch(commerceCacheManagerProvider),
    scope: ref.watch(locationScopeProvider).cacheKey,
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

/// One level of the serving store's PRIVATE category tree; the family argument is
/// the parent category id (null = top level). Backs the Categories tab's rail.
final storeCategoriesProvider =
    FutureProvider.family<List<Category>, String?>((ref, parentId) async =>
        _unwrap(await ref
            .watch(catalogRepositoryProvider)
            .getStoreCategories(parentId: parentId)));

/// The serving store's own products in a category — the store tree's leaf grid.
final storeProductsProvider = FutureProvider.family<List<Product>, String>(
  (ref, categoryId) async => _unwrap(await ref
      .watch(catalogRepositoryProvider)
      .getStoreProducts(categoryId: categoryId)),
);

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

/// Popular products for the home rail — a single popularity-sorted server page
/// (`/products?sort=popular`), not a full-catalog sweep.
final popularProductsProvider = FutureProvider<List<Product>>((ref) async {
  final popular =
      _unwrap(await ref.watch(catalogRepositoryProvider).getPopular());
  return popular.take(6).toList();
});

final searchProductsProvider = FutureProvider.family<List<Product>, String>(
  (ref, query) async =>
      _unwrap(await ref.watch(catalogRepositoryProvider).search(query)),
);

/// As-you-type autocomplete for the search screen. Cheap enough to fire on every
/// (debounced) keystroke; returns products, completion terms and categories.
final searchSuggestionsProvider =
    FutureProvider.family<SearchSuggestions, String>(
  (ref, query) async {
    final q = query.trim();
    if (q.isEmpty) return SearchSuggestions.empty;
    return _unwrap(await ref.watch(catalogRepositoryProvider).suggest(q));
  },
);
