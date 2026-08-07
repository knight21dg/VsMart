import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../cart/presentation/providers/cart_providers.dart';
import '../../../wishlist/presentation/providers/wishlist_providers.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/product.dart';
import '../category_icons.dart';
import '../product_navigation.dart';
import '../providers/catalog_providers.dart';
import '../widgets/cart_summary_bar.dart';
import '../widgets/product_overlay.dart';
import '../widgets/vs_product_grid.dart';

/// Categories tab — a RECURSIVE two-pane browser over the serving store's own
/// (private) products.
///
/// Every level looks the same:
///  * LEFT: the categories at this level, as a vertical rail;
///  * RIGHT: the children of the selected rail entry — or, once that entry is a
///    leaf, its products.
///
/// Tapping a child pushes the next level, where the rail becomes that child's
/// siblings (with it selected) and the right pane shows the next step down. So
/// departments → sub-categories → products all reuse one layout, and Back walks
/// the stack up one level at a time.
///
/// Scope is deliberately STRICT: only products the serving store created for
/// itself ([Product.origin_store]) appear. With no serving store — or a store
/// that has added nothing — the tab shows its empty state rather than quietly
/// falling back to the company-wide catalog, which would put another shop's
/// departments in the rail.
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

/// One rung of the drill-down: the categories listed in the rail, and which of
/// them is open in the right pane.
class _Level {
  _Level({this.railParentId, this.selectedId, this.title});

  /// Parent whose children fill the rail; null at the top level.
  final String? railParentId;

  /// The open rail entry. Null falls back to the first entry, so a level is
  /// always showing something.
  String? selectedId;

  /// Name of the category we drilled through to get here (for the breadcrumb).
  final String? title;
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  /// The drill-down stack; index 0 is the top level and is never popped.
  final List<_Level> _stack = [_Level()];
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  _Level get _current => _stack.last;

  void _clearSearch() {
    _query = '';
    _searchController.clear();
  }

  /// Open [child] of [parent]: the next level's rail is [parent]'s children, so
  /// the child's siblings stay reachable one tap away.
  void _drillInto({required Category parent, required Category child}) {
    ref
        .read(analyticsServiceProvider)
        .track('store_category_opened', {'category': child.id});
    setState(() {
      _stack.add(_Level(
        railParentId: parent.id,
        selectedId: child.id,
        title: child.name,
      ));
      _clearSearch();
    });
  }

  void _select(String categoryId) => setState(() {
        _current.selectedId = categoryId;
        _clearSearch();
      });

  /// True when a level was popped — i.e. Back was handled here.
  bool _popLevel() {
    if (_stack.length <= 1) return false;
    setState(() {
      _stack.removeLast();
      _clearSearch();
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final rail = ref.watch(storeCategoriesProvider(_current.railParentId));
    final cart = ref.watch(cartControllerProvider);
    final nested = _stack.length > 1;

    return PopScope(
      // Back should walk UP the hierarchy before it leaves the tab.
      canPop: !nested,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _popLevel();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_current.title ?? context.l10n.navCategories),
          leading: nested
              ? IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _popLevel,
                )
              : null,
          actions: [
            IconButton(
              icon: Badge(
                isLabelVisible: cart.itemCount > 0,
                label: Text('${cart.itemCount}'),
                child: const Icon(Icons.shopping_cart_outlined),
              ),
              onPressed: () => context.goNamed(RouteNames.cart),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: rail.when(
                loading: () => const VSLoadingView(),
                error: (e, _) => VSErrorView(
                  failure: e is Failure ? e : null,
                  onRetry: () => ref.invalidate(
                      storeCategoriesProvider(_current.railParentId)),
                ),
                data: (items) {
                  if (items.isEmpty) return const _NoStoreProducts();
                  final selected = items.firstWhere(
                    (c) => c.id == _current.selectedId,
                    orElse: () => items.first,
                  );
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 96,
                        child: _CategoryRail(
                          items: items,
                          selectedId: selected.id,
                          onSelect: _select,
                        ),
                      ),
                      Expanded(
                        child: _DetailPane(
                          selected: selected,
                          query: _query,
                          searchController: _searchController,
                          onQuery: (v) =>
                              setState(() => _query = v.trim().toLowerCase()),
                          onOpenChild: (child) =>
                              _drillInto(parent: selected, child: child),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
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
    );
  }
}

/// The right pane: [selected]'s sub-categories, or its products once it's a leaf.
class _DetailPane extends ConsumerWidget {
  const _DetailPane({
    required this.selected,
    required this.query,
    required this.searchController,
    required this.onQuery,
    required this.onOpenChild,
  });

  final Category selected;
  final String query;
  final TextEditingController searchController;
  final ValueChanged<String> onQuery;
  final ValueChanged<Category> onOpenChild;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
          child: VSSearchField(
            controller: searchController,
            hint: selected.hasChildren
                ? context.l10n.catalogSearchCategories
                : context.l10n.searchHint,
            onChanged: onQuery,
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) context.pushNamed(RouteNames.search);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, 0, AppSpacing.lg, AppSpacing.sm),
          child: Text(selected.name, style: AppTypography.titleLarge),
        ),
        Expanded(
          child: selected.hasChildren
              ? _ChildCategories(
                  parent: selected, query: query, onOpen: onOpenChild)
              : _LeafProducts(category: selected, query: query),
        ),
      ],
    );
  }
}

class _ChildCategories extends ConsumerWidget {
  const _ChildCategories({
    required this.parent,
    required this.query,
    required this.onOpen,
  });

  final Category parent;
  final String query;
  final ValueChanged<Category> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final children = ref.watch(storeCategoriesProvider(parent.id));
    return children.when(
      loading: () => const VSLoadingView(),
      error: (e, _) => VSErrorView(
        failure: e is Failure ? e : null,
        onRetry: () => ref.invalidate(storeCategoriesProvider(parent.id)),
      ),
      data: (all) {
        final results = query.isEmpty
            ? all
            : all.where((c) => c.name.toLowerCase().contains(query)).toList();
        if (results.isEmpty) {
          return VSEmptyState(
            icon: Icons.search_off_rounded,
            title: context.l10n.catalogNoCategories,
            message: 'No sub-categories match "$query".',
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(storeCategoriesProvider(parent.id));
            await ref.read(storeCategoriesProvider(parent.id).future);
          },
          child: GridView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding:
                const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.lg, 96),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: AppSpacing.md,
              crossAxisSpacing: AppSpacing.md,
              childAspectRatio: 0.72,
            ),
            itemCount: results.length,
            itemBuilder: (_, i) => _CategoryTile(
              category: results[i],
              onTap: () => onOpen(results[i]),
            ),
          ),
        );
      },
    );
  }
}

/// The deepest level: the store's own products in this category.
class _LeafProducts extends ConsumerWidget {
  const _LeafProducts({required this.category, required this.query});

  final Category category;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(storeProductsProvider(category.id));
    final cart = ref.watch(cartControllerProvider);
    final wishlist = ref.watch(wishlistProvider);

    return products.when(
      loading: () => const VSLoadingView(),
      error: (e, _) => VSErrorView(
        failure: e is Failure ? e : null,
        onRetry: () => ref.invalidate(storeProductsProvider(category.id)),
      ),
      data: (all) {
        final results = query.isEmpty
            ? all
            : all
                .where((p) =>
                    p.name.toLowerCase().contains(query) ||
                    p.brand.toLowerCase().contains(query))
                .toList();
        if (results.isEmpty) {
          return VSEmptyState(
            icon: query.isEmpty
                ? Icons.inventory_2_outlined
                : Icons.search_off_rounded,
            title: query.isEmpty
                ? context.l10n.catalogNoProducts
                : context.l10n.searchNoResults,
            message: query.isEmpty
                ? 'This category is empty right now.'
                : 'No products match "$query".',
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(storeProductsProvider(category.id));
            await ref.read(storeProductsProvider(category.id).future);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, 0, AppSpacing.lg, 96),
                sliver: VSProductGrid(
                  products: results,
                  heroTags: true,
                  onTap: (p) => showProductOverlay(
                    context,
                    products: results,
                    initialIndex: results.indexWhere((x) => x.id == p.id),
                  ),
                  onAdd: (p) {
                    addToCartOrChoose(context, ref, p,
                        source: 'store_category');
                    ref.read(analyticsServiceProvider).track('add_to_cart',
                        {'product': p.id, 'source': 'store_category'});
                  },
                  quantityOf: (p) => cart.quantityOf(p.id),
                  isWishlisted: (p) => wishlist.contains(p.id),
                  onWishlistToggle: (p) =>
                      ref.read(wishlistProvider.notifier).toggle(p.id),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Shown when the serving store has no products of its own — or when no store
/// serves this location at all. Both are the same thing to the customer: there
/// is nothing here to browse yet, so we say so clearly and point them at the one
/// remedy that helps — changing the delivery location (zone).
class _NoStoreProducts extends StatelessWidget {
  const _NoStoreProducts();

  @override
  Widget build(BuildContext context) {
    return VSEmptyState(
      icon: Icons.storefront_outlined,
      accent: context.vsColors.offer,
      title: 'No products in this zone yet',
      message:
          "We're not stocking your area yet. Try a different delivery location, "
          'or check back soon.',
      actionLabel: context.l10n.serviceChangeLocation,
      onAction: () => context.pushNamed(RouteNames.addresses),
    );
  }
}

class _CategoryRail extends StatelessWidget {
  const _CategoryRail({
    required this.items,
    required this.selectedId,
    required this.onSelect,
  });

  final List<Category> items;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      color: vs.brandTint.withValues(alpha: 0.35),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final category = items[i];
          final active = category.id == selectedId;
          return InkWell(
            onTap: () => onSelect(category.id),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.md, horizontal: AppSpacing.xs),
              decoration: BoxDecoration(
                color: active ? context.colors.surface : null,
                border: Border(
                  left: BorderSide(
                    color: active ? vs.brand : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                children: [
                  _CatThumb(category: category, size: 44),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    category.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelSmall.copyWith(
                      color: active ? vs.brand : vs.textSecondary,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onTap});

  final Category category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brLg,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: AppRadius.brLg,
          border: Border.all(color: vs.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _CatThumb(category: category, size: 56),
            AppSpacing.vGapSm,
            Text(
              category.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// A category thumbnail — the category image when present (the backend falls back
/// to a photo of a product inside the category, so store-created categories get a
/// real picture without curated artwork), else the data-driven icon in a tinted
/// circle.
class _CatThumb extends StatelessWidget {
  const _CatThumb({required this.category, required this.size});

  final Category category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final img = category.imageUrl;
    if (img != null && img.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 4),
        child: VSNetworkImage(
          url: img,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(color: vs.brandTint, shape: BoxShape.circle),
      child: Icon(
        categoryIcon(category.iconName),
        color: vs.brand,
        size: size * 0.5,
      ),
    );
  }
}
