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
  static const _pageSize = 6;
  static const _gridPrefKey = 'listing_grid';

  List<Product> _raw = const [];

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
    final repo = ref.read(catalogRepositoryProvider);
    final result = arg.isSearch
        ? await repo.search(arg.query!)
        : await repo.getProducts(categoryId: arg.categoryId);
    result.fold(
      (failure) => state = state.copyWith(loading: false, error: failure),
      (products) {
        _raw = products;
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
    if (!state.hasMore || state.loadingMore || state.loading) return;
    state = state.copyWith(loadingMore: true);
    // Simulated page latency; a remote source would fetch the next page here.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _emitPage(state.page + 1);
  }

  // --- internals ---------------------------------------------------------

  void _recomputeAndEmit() {
    final filtered = _raw.where(state.filter.matches).toList();
    _sorted(filtered);
    _all = filtered;
    _emitPage(0);
  }

  List<Product> _all = const [];

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

  void _emitPage(int page) {
    final end = ((page + 1) * _pageSize).clamp(0, _all.length);
    state = state.copyWith(
      products: _all.take(end).toList(),
      loading: false,
      loadingMore: false,
      hasMore: end < _all.length,
      page: page,
      totalCount: _all.length,
      clearError: true,
    );
  }
}

final listingControllerProvider =
    NotifierProvider.family<ListingController, ListingState, ListingArgs>(
        ListingController.new);
