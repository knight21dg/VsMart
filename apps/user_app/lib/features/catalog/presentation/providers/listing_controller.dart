import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/product_filter.dart';
import 'catalog_providers.dart';

/// Identifies a listing context. The same engine serves a category listing
/// (`categoryId`) and search results (`query`) — Search reuses this directly.
class ListingArgs extends Equatable {
  const ListingArgs({this.categoryId, this.query});

  final String? categoryId;
  final String? query;

  bool get isSearch => (query ?? '').trim().isNotEmpty;

  @override
  List<Object?> get props => [categoryId, query];
}

/// Full state of a product listing: the visible (paginated) products plus the
/// active filter, sort, view mode and pagination flags.
class ListingState extends Equatable {
  const ListingState({
    required this.products,
    required this.filter,
    required this.sort,
    required this.gridMode,
    required this.loading,
    required this.loadingMore,
    required this.hasMore,
    required this.page,
    required this.totalCount,
    this.error,
  });

  final List<Product> products;
  final ProductFilter filter;
  final ProductSort sort;
  final bool gridMode;
  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final int page;
  final int totalCount;
  final Failure? error;

  bool get isEmpty => !loading && error == null && products.isEmpty;

  ListingState copyWith({
    List<Product>? products,
    ProductFilter? filter,
    ProductSort? sort,
    bool? gridMode,
    bool? loading,
    bool? loadingMore,
    bool? hasMore,
    int? page,
    int? totalCount,
    Failure? error,
    bool clearError = false,
  }) {
    return ListingState(
      products: products ?? this.products,
      filter: filter ?? this.filter,
      sort: sort ?? this.sort,
      gridMode: gridMode ?? this.gridMode,
      loading: loading ?? this.loading,
      loadingMore: loadingMore ?? this.loadingMore,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      totalCount: totalCount ?? this.totalCount,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [
        products,
        filter,
        sort,
        gridMode,
        loading,
        loadingMore,
        hasMore,
        page,
        totalCount,
        error,
      ];
}

/// Drives a product listing: fetch → filter → sort → paginate, with grid/list
/// preference persisted. Filtering/sorting run over the fetched set so Search,
/// Offers and Wishlist can share one engine.
class ListingController extends FamilyNotifier<ListingState, ListingArgs> {
  /// Server page size — one network round-trip per scroll page (NOT the whole
  /// category up front).
  static const _serverPageSize = 20;
  static const _gridPrefKey = 'listing_grid';

  /// Products accumulated across the server pages fetched so far. Grows one
  /// server page at a time as [loadMore] runs; filter/sort are applied over it.
  List<Product> _raw = const [];

  /// The last server page number successfully loaded (0 = none yet).
  int _loadedPage = 0;

  /// Whether the server reported more pages after [_loadedPage].
  bool _serverHasMore = false;

  /// The server's total item count for this query (whole category, not just the
  /// pages fetched).
  int _serverTotal = 0;

  @override
  ListingState build(ListingArgs arg) {
    final grid = ref.read(hiveServiceProvider).settingsBox.get(
          _gridPrefKey,
          defaultValue: true,
        ) as bool;
    Future.microtask(load);
    return ListingState(
      products: const [],
      filter: ProductFilter.empty,
      sort: ProductSort.popularity,
      gridMode: grid,
      loading: true,
      loadingMore: false,
      hasMore: false,
      page: 0,
      totalCount: 0,
    );
  }

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    _raw = const [];
    _loadedPage = 0;
    _serverHasMore = false;
    _serverTotal = 0;
    final result = await ref.read(catalogRepositoryProvider).getProductsPage(
          categoryId: arg.isSearch ? null : arg.categoryId,
          query: arg.isSearch ? arg.query : null,
          page: 1,
          pageSize: _serverPageSize,
        );
    result.fold(
      (failure) => state = state.copyWith(loading: false, error: failure),
      (page) {
        _raw = page.items;
        _loadedPage = page.meta.currentPage;
        _serverHasMore = page.hasMore;
        _serverTotal = page.meta.total;
        _recomputeAndEmit();
      },
    );
  }

  Future<void> refresh() => load();

  void setSort(ProductSort sort) {
    if (sort == state.sort) return;
    state = state.copyWith(sort: sort);
    ref.read(analyticsServiceProvider).track('sort_changed', {'sort': sort.name});
    _recomputeAndEmit();
  }

  void applyFilter(ProductFilter filter) {
    state = state.copyWith(filter: filter);
    ref.read(analyticsServiceProvider).track('filter_applied', {
      'active': filter.isActive,
    });
    _recomputeAndEmit();
  }

  void toggleViewMode() {
    final next = !state.gridMode;
    state = state.copyWith(gridMode: next);
    ref.read(hiveServiceProvider).settingsBox.put(_gridPrefKey, next);
  }

  Future<void> loadMore() async {
    if (!_serverHasMore || state.loadingMore || state.loading) return;
    state = state.copyWith(loadingMore: true);
    // Real network: fetch the NEXT server page and append it.
    final result = await ref.read(catalogRepositoryProvider).getProductsPage(
          categoryId: arg.isSearch ? null : arg.categoryId,
          query: arg.isSearch ? arg.query : null,
          page: _loadedPage + 1,
          pageSize: _serverPageSize,
        );
    result.fold(
      // Keep the pages already loaded; just stop the spinner so a transient
      // failure doesn't wipe the list. The next scroll retries.
      (_) => state = state.copyWith(loadingMore: false),
      (page) {
        _raw = [..._raw, ...page.items];
        _loadedPage = page.meta.currentPage;
        _serverHasMore = page.hasMore;
        _serverTotal = page.meta.total;
        _recomputeAndEmit();
      },
    );
  }

  // --- internals ---------------------------------------------------------

  /// Re-derives the visible list from the pages loaded so far: filter → sort →
  /// emit. Pagination is driven by the SERVER (`_serverHasMore`), so this shows
  /// every loaded-and-matching product rather than a client-side slice.
  void _recomputeAndEmit() {
    final filtered = _raw.where(state.filter.matches).toList();
    _sorted(filtered);
    state = state.copyWith(
      products: filtered,
      loading: false,
      loadingMore: false,
      hasMore: _serverHasMore,
      page: _loadedPage,
      // When filtering client-side we can only count the loaded matches; with no
      // filter the server's total is the true category size.
      totalCount: state.filter.isActive ? filtered.length : _serverTotal,
      clearError: true,
    );
  }

  void _sorted(List<Product> list) {
    switch (state.sort) {
      case ProductSort.popularity:
        list.sort((a, b) => b.reviews.compareTo(a.reviews));
      case ProductSort.priceLowToHigh:
        list.sort((a, b) => a.price.compareTo(b.price));
      case ProductSort.priceHighToLow:
        list.sort((a, b) => b.price.compareTo(a.price));
      case ProductSort.discount:
        list.sort((a, b) => b.discountPercent.compareTo(a.discountPercent));
      case ProductSort.newest:
        break; // preserve source order
    }
  }
}

final listingControllerProvider =
    NotifierProvider.family<ListingController, ListingState, ListingArgs>(
        ListingController.new);
