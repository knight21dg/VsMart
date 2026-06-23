import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../cart/presentation/providers/cart_providers.dart';
import '../../../offers/presentation/widgets/placement_banner_carousel.dart';
import '../../../wishlist/presentation/providers/wishlist_providers.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/product_filter.dart';
import '../providers/catalog_providers.dart';
import '../providers/listing_controller.dart';
import '../widgets/cart_summary_bar.dart';
import '../widgets/product_overlay.dart';
import '../widgets/vs_filter_chip.dart';
import '../widgets/vs_filter_sheet.dart';
import '../widgets/vs_pagination_loader.dart';
import '../widgets/vs_product_grid.dart';
import '../widgets/vs_product_list_tile.dart';
import '../widgets/vs_sort_bottom_sheet.dart';

/// Product listing powered by the [ListingController] engine: sort, filter,
/// active-filter chips, grid/list toggle (persisted), pagination, and full
/// loading/empty/error/offline states. Search reuses the same engine via
/// [ListingArgs.query].
class ProductListingScreen extends ConsumerStatefulWidget {
  const ProductListingScreen({
    super.key,
    this.categoryId,
    this.query,
    this.title = 'Products',
  });

  final String? categoryId;
  final String? query;
  final String title;

  @override
  ConsumerState<ProductListingScreen> createState() =>
      _ProductListingScreenState();
}

class _ProductListingScreenState extends ConsumerState<ProductListingScreen> {
  final _scroll = ScrollController();
  late final String? _departmentId = widget.categoryId;
  late String? _selectedCategoryId = widget.categoryId;
  late String _title = widget.title;

  ListingArgs get _args =>
      ListingArgs(categoryId: _selectedCategoryId, query: widget.query);

  /// Switch the listing between the department ("All") and its subcategories
  /// from the side rail — in place, no new route.
  void _selectListingCategory(String? id, String title) {
    if (id == _selectedCategoryId) return;
    setState(() {
      _selectedCategoryId = id;
      _title = title;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(analyticsServiceProvider).track('listing_viewed', {
        if (widget.categoryId != null) 'category': widget.categoryId!,
        if (widget.query != null) 'query': widget.query!,
      });
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 240) {
      ref.read(listingControllerProvider(_args).notifier).loadMore();
    }
  }

  ListingController get _controller =>
      ref.read(listingControllerProvider(_args).notifier);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(listingControllerProvider(_args));
    final cart = ref.watch(cartControllerProvider);
    final wishlist = ref.watch(wishlistProvider);
    final connectivity = ref.watch(commerceConnectivityProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () => context.pushNamed(RouteNames.search),
          ),
          IconButton(
            icon: Icon(state.gridMode
                ? Icons.view_list_rounded
                : Icons.grid_view_rounded),
            onPressed: _controller.toggleViewMode,
          ),
          IconButton(
            icon: Badge(
              isLabelVisible: cart.itemCount > 0,
              label: Text('${cart.itemCount}'),
              child: const Icon(Icons.shopping_cart_outlined),
            ),
            onPressed: () => context.goNamed(RouteNames.cart),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: Row(
        children: [
          // Left-side subcategory rail — switch between the department ("All")
          // and its subcategories in place (Instamart/Blinkit style). Hidden for
          // search results and departments with no subcategories.
          if (widget.query == null && _departmentId != null)
            _SideCategoryRail(
              departmentId: _departmentId,
              selectedId: _selectedCategoryId,
              onSelectAll: () =>
                  _selectListingCategory(_departmentId, widget.title),
              onSelect: (c) => _selectListingCategory(c.id, c.name),
            ),
          Expanded(
            child: Stack(
              children: [
                Column(
            children: [
              VSOfflineBanner(
                offline: connectivity == CommerceConnectivity.offline,
                syncing: connectivity == CommerceConnectivity.syncing,
              ),
              _Toolbar(
                state: state,
                onSort: _openSort,
                onFilter: _openFilter,
              ),
              if (state.filter.isActive)
                _ActiveFilters(
                  state: state,
                  onApply: _controller.applyFilter,
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _controller.refresh,
                  child: _Body(
                    state: state,
                    scroll: _scroll,
                    bannerCategoryId: _departmentId ?? _selectedCategoryId,
                    bannerSubcategoryId:
                        (_selectedCategoryId != null &&
                                _selectedCategoryId != _departmentId)
                            ? _selectedCategoryId
                            : null,
                    // Leave room so the floating cart pill never covers the
                    // last row of products.
                    bottomInset: cart.itemCount > 0 ? 84 : 0,
                    onRetry: _controller.load,
                    onOpen: (p) => showProductOverlay(
                      context,
                      products: state.products,
                      initialIndex:
                          state.products.indexWhere((x) => x.id == p.id),
                    ),
                    onAdd: (p) {
                      ref.read(cartControllerProvider.notifier).addProduct(p);
                      ref.read(analyticsServiceProvider).track('add_to_cart',
                          {'product': p.id, 'source': 'listing'});
                    },
                    quantityOf: (p) => cart.quantityOf(p.id),
                    isWishlisted: (p) => wishlist.contains(p.id),
                    onWishlistToggle: (p) =>
                        ref.read(wishlistProvider.notifier).toggle(p.id),
                  ),
                ),
              ),
            ],
          ),
          // Floating cart pill overlay — sits above the list instead of
          // consuming layout height and cutting it off.
          Align(
            alignment: Alignment.bottomCenter,
            child: CartSummaryBar(
              itemCount: cart.itemCount,
              total: cart.itemTotal,
              onViewCart: () => context.goNamed(RouteNames.cart),
            ),
          ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSort() async {
    final current = ref.read(listingControllerProvider(_args)).sort;
    final sort = await showVSSortBottomSheet(context, current);
    if (sort != null) _controller.setSort(sort);
  }

  Future<void> _openFilter() async {
    final state = ref.read(listingControllerProvider(_args));
    final brands = state.products.map((p) => p.brand).toSet().toList()..sort();
    final filter = await showVSFilterSheet(
      context,
      current: state.filter,
      brands: brands,
    );
    if (filter != null) _controller.applyFilter(filter);
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.state,
    required this.onSort,
    required this.onFilter,
  });

  final ListingState state;
  final VoidCallback onSort;
  final VoidCallback onFilter;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
      child: Row(
        children: [
          VSFilterChip(
            label: 'Sort',
            icon: Icons.swap_vert_rounded,
            onTap: onSort,
          ),
          AppSpacing.hGapSm,
          VSFilterChip(
            label: 'Filter',
            icon: Icons.tune_rounded,
            selected: state.filter.isActive,
            onTap: onFilter,
          ),
          const Spacer(),
          Text(
            state.loading ? '…' : '${state.totalCount} items',
            style: AppTypography.labelMedium.copyWith(color: vs.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({required this.state, required this.onApply});

  final ListingState state;
  final ValueChanged<ProductFilter> onApply;

  @override
  Widget build(BuildContext context) {
    final chips = state.filter.activeChips();
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: AppSpacing.screenHorizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => AppSpacing.hGapSm,
        itemBuilder: (_, i) => VSFilterChip(
          label: chips[i].label,
          selected: true,
          onRemove: () => onApply(chips[i].cleared),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.state,
    required this.scroll,
    required this.bottomInset,
    required this.onRetry,
    required this.onOpen,
    required this.onAdd,
    required this.quantityOf,
    required this.isWishlisted,
    required this.onWishlistToggle,
    this.bannerCategoryId,
    this.bannerSubcategoryId,
  });

  final ListingState state;
  final ScrollController scroll;
  final double bottomInset;
  final String? bannerCategoryId;
  final String? bannerSubcategoryId;
  final VoidCallback onRetry;
  final ValueChanged<Product> onOpen;
  final ValueChanged<Product> onAdd;
  final int Function(Product) quantityOf;
  final bool Function(Product) isWishlisted;
  final ValueChanged<Product> onWishlistToggle;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: AppSpacing.screen,
            child: _Hero(title: _heroTitle(context)),
          ),
        ),
        // Dynamic, category-targeted promotional banners (renders nothing when
        // the server returns no banners for this listing).
        SliverToBoxAdapter(
          child: PlacementBannerCarousel(
            placement: 'product_list',
            categoryId: bannerCategoryId,
            subcategoryId: bannerSubcategoryId,
            trailingGap: AppSpacing.lg,
          ),
        ),
        if (state.loading && state.products.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: VSLoadingView(),
          )
        else if (state.error != null && state.products.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: VSErrorView(failure: state.error, onRetry: onRetry),
          )
        else if (state.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: VSEmptyState(
              title: 'No products found',
              message: 'Try adjusting your filters or search.',
              icon: Icons.search_off_rounded,
            ),
          )
        else ...[
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
                AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg + bottomInset),
            sliver: state.gridMode
                ? VSProductGrid(
                    products: state.products,
                    onTap: onOpen,
                    onAdd: onAdd,
                    quantityOf: quantityOf,
                    isWishlisted: isWishlisted,
                    onWishlistToggle: onWishlistToggle,
                    heroTags: true,
                  )
                : SliverList.separated(
                    itemCount: state.products.length,
                    separatorBuilder: (_, __) => AppSpacing.vGapMd,
                    itemBuilder: (_, i) {
                      final p = state.products[i];
                      return VSProductListTile(
                        product: p,
                        quantity: quantityOf(p),
                        heroTag: productHeroTag(p.id),
                        onTap: () => onOpen(p),
                        onAdd: () => onAdd(p),
                      );
                    },
                  ),
          ),
          if (state.loadingMore)
            const SliverToBoxAdapter(child: VSPaginationLoader()),
        ],
      ],
    );
  }

  String _heroTitle(BuildContext context) => 'Fresh & Healthy';
}

/// Vertical category rail down the right edge of the listing. Tapping a tile
/// swaps the products in place (no new screen), like Instamart / Blinkit.
class _SideCategoryRail extends ConsumerWidget {
  const _SideCategoryRail({
    required this.departmentId,
    required this.selectedId,
    required this.onSelectAll,
    required this.onSelect,
  });

  final String departmentId;
  final String? selectedId;
  final VoidCallback onSelectAll;
  final ValueChanged<Category> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    final subs = ref.watch(categoriesProvider(departmentId)).valueOrNull ??
        const <Category>[];
    if (subs.isEmpty) return const SizedBox.shrink();
    return Container(
      width: 82,
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(right: BorderSide(color: vs.border)),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        children: [
          _RailTile(
            label: 'All',
            icon: Icons.grid_view_rounded,
            selected: selectedId == departmentId,
            onTap: onSelectAll,
          ),
          for (final c in subs)
            _RailTile(
              label: c.name,
              imageUrl: c.imageUrl,
              selected: c.id == selectedId,
              onTap: () => onSelect(c),
            ),
        ],
      ),
    );
  }
}

class _RailTile extends StatelessWidget {
  const _RailTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.imageUrl,
    this.icon = Icons.category_rounded,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? imageUrl;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: 5),
        decoration: BoxDecoration(
          color: selected ? vs.brandTint : null,
          border: Border(
            right: BorderSide(
              color: selected ? vs.brand : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Column(
          children: [
            Container(
              height: 52,
              width: 52,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: selected
                    ? context.colors.surface
                    : vs.border.withValues(alpha: 0.3),
                shape: BoxShape.circle,
                border: selected ? Border.all(color: vs.brand) : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: imageUrl == null
                  ? Icon(icon,
                      color: selected ? vs.brand : vs.textSecondary, size: 24)
                  : VSNetworkImage(
                      url: imageUrl,
                      fit: BoxFit.contain,
                      fallbackIcon: icon,
                    ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelSmall.copyWith(
                color: selected ? vs.brand : vs.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 10,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [vs.brandTint, vs.brandTint.withValues(alpha: 0.3)],
        ),
        borderRadius: AppRadius.brLg,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTypography.labelMedium.copyWith(color: vs.brand)),
                const SizedBox(height: 2),
                Text('Handpicked daily from trusted farms',
                    style: AppTypography.bodySmall
                        .copyWith(color: vs.textSecondary)),
              ],
            ),
          ),
          Container(
            height: 56,
            width: 56,
            decoration: BoxDecoration(
                color: context.colors.surface, shape: BoxShape.circle),
            child: Icon(Icons.eco_rounded, color: vs.brand, size: 30),
          ),
        ],
      ),
    );
  }
}
