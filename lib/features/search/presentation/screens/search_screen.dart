import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../cart/presentation/providers/cart_providers.dart';
import '../../../catalog/domain/entities/product.dart';
import '../../../catalog/presentation/product_navigation.dart';
import '../../../catalog/presentation/providers/catalog_providers.dart';
import '../../../wishlist/presentation/providers/wishlist_providers.dart';
import '../providers/search_providers.dart';

enum _Sort { popularity, priceLow, rating }

/// Catalog search — recent + trending suggestions before typing, and a results
/// view (filter chips, count, sort, product grid) matching the design.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();

  bool _underPrice = false;
  bool _topRated = false;
  _Sort _sort = _Sort.popularity;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setQuery(String value) =>
      ref.read(searchQueryProvider.notifier).state = value.trim();

  void _submit(String value) {
    final q = value.trim();
    if (q.isEmpty) return;
    ref.read(recentSearchesProvider.notifier).add(q);
    _setQuery(q);
    context.hideKeyboard();
  }

  void _runTerm(String term) {
    _controller.text = term;
    _controller.selection = TextSelection.collapsed(offset: term.length);
    _submit(term);
  }

  /// Advanced-filters bottom sheet: tune the quick filters + sort order.
  Future<void> _openFilters() async {
    var underPrice = _underPrice;
    var topRated = _topRated;
    var sort = _sort;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: AppSpacing.screen,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Filters & Sort', style: AppTypography.titleLarge),
              AppSpacing.vGapMd,
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Under ₹99'),
                value: underPrice,
                onChanged: (v) => setSheet(() => underPrice = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Top Rated (4★ and above)'),
                value: topRated,
                onChanged: (v) => setSheet(() => topRated = v),
              ),
              const Divider(),
              Text('Sort by', style: AppTypography.titleMedium),
              for (final option in _Sort.values)
                RadioListTile<_Sort>(
                  contentPadding: EdgeInsets.zero,
                  title: Text(switch (option) {
                    _Sort.popularity => 'Popularity',
                    _Sort.priceLow => 'Price: Low to High',
                    _Sort.rating => 'Rating',
                  }),
                  value: option,
                  groupValue: sort,
                  onChanged: (v) => setSheet(() => sort = v!),
                ),
              AppSpacing.vGapMd,
              SizedBox(
                width: double.infinity,
                child: VSButton(
                  label: 'Apply Filters',
                  onPressed: () => Navigator.of(ctx).pop(true),
                ),
              ),
              AppSpacing.vGapSm,
            ],
          ),
        ),
      ),
    );
    if (result == true && mounted) {
      setState(() {
        _underPrice = underPrice;
        _topRated = topRated;
        _sort = sort;
      });
    }
  }

  List<Product> _apply(List<Product> input) {
    var list = input.where((p) {
      if (_underPrice && p.price >= 99) return false;
      if (_topRated && p.rating < 4) return false;
      return true;
    }).toList();
    switch (_sort) {
      case _Sort.popularity:
        list.sort((a, b) => b.reviews.compareTo(a.reviews));
      case _Sort.priceLow:
        list.sort((a, b) => a.price.compareTo(b.price));
      case _Sort.rating:
        list.sort((a, b) => b.rating.compareTo(a.rating));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        title: VSSearchField(
          controller: _controller,
          autofocus: true,
          hint: 'Search for groceries, brands…',
          onChanged: _setQuery,
          onSubmitted: _submit,
        ),
      ),
      body: SafeArea(
        top: false,
        child: query.isEmpty
            ? _Suggestions(onTerm: _runTerm)
            : _results(query),
      ),
    );
  }

  Widget _results(String query) {
    final async = ref.watch(searchProductsProvider(query));
    final activeFilters = (_underPrice ? 1 : 0) + (_topRated ? 1 : 0);

    return async.when(
      loading: () => const VSLoadingView(),
      error: (e, _) => VSErrorView(
        failure: e is Failure ? e : null,
        onRetry: () => ref.invalidate(searchProductsProvider(query)),
      ),
      data: (raw) {
        final products = _apply(raw);
        return Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FilterBar(
                  underPrice: _underPrice,
                  topRated: _topRated,
                  onUnderPrice: () =>
                      setState(() => _underPrice = !_underPrice),
                  onTopRated: () => setState(() => _topRated = !_topRated),
                  onFilters: _openFilters,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.sm),
                  child: Row(
                    children: [
                      Text('${products.length} Results found',
                          style: AppTypography.labelMedium),
                      const Spacer(),
                      _SortButton(
                        sort: _sort,
                        onChanged: (s) => setState(() => _sort = s),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: products.isEmpty
                      ? VSEmptyState(
                          title: 'No results',
                          message:
                              'We couldn\'t find anything for "$query".',
                          icon: Icons.search_off_rounded,
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                              0, AppSpacing.lg, AppSpacing.huge),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: AppSpacing.md,
                            crossAxisSpacing: AppSpacing.md,
                            childAspectRatio: 0.62,
                          ),
                          itemCount: products.length,
                          itemBuilder: (context, i) =>
                              _ResultCard(product: products[i]),
                        ),
                ),
              ],
            ),
            if (activeFilters > 0)
              Positioned(
                bottom: AppSpacing.lg,
                left: 0,
                right: 0,
                child: Center(child: _FiltersPill(count: activeFilters)),
              ),
          ],
        );
      },
    );
  }
}

class _ResultCard extends ConsumerWidget {
  const _ResultCard({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = product;
    final qty = ref.watch(cartControllerProvider).quantityOf(p.id);
    final wishlisted = ref.watch(isWishlistedProvider(p.id));
    return VSProductCard(
      name: p.name,
      unitLabel: p.unit,
      price: p.price,
      mrp: p.mrp,
      rating: p.rating,
      reviews: p.reviews,
      imageUrl: p.imageUrl,
      outOfStock: !p.inStock,
      inWishlist: wishlisted,
      quantityInCart: qty,
      heroTag: detailHeroTag('search', p.id),
      onWishlistTap: () => ref.read(wishlistProvider.notifier).toggle(p.id),
      onTap: () =>
          openProductDetail(context, productId: p.id, source: 'search'),
      onAdd: () => ref.read(cartControllerProvider.notifier).addProduct(p),
      onIncrement: () =>
          ref.read(cartControllerProvider.notifier).increment(p.id),
      onDecrement: () =>
          ref.read(cartControllerProvider.notifier).decrement(p.id),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.underPrice,
    required this.topRated,
    required this.onUnderPrice,
    required this.onTopRated,
    required this.onFilters,
  });

  final bool underPrice;
  final bool topRated;
  final VoidCallback onUnderPrice;
  final VoidCallback onTopRated;
  final VoidCallback onFilters;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
      child: Row(
        children: [
          _Chip(
            label: 'Filters',
            icon: Icons.tune_rounded,
            selected: false,
            onTap: onFilters,
          ),
          AppSpacing.hGapSm,
          _Chip(
            label: 'Under ₹99',
            selected: underPrice,
            onTap: onUnderPrice,
          ),
          AppSpacing.hGapSm,
          _Chip(
            label: 'Top Rated',
            icon: Icons.star_rounded,
            selected: topRated,
            onTap: onTopRated,
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final fg = selected ? vs.brand : context.colors.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brPill,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? vs.brandTint : context.colors.surface,
          borderRadius: AppRadius.brPill,
          border: Border.all(color: selected ? vs.brand : vs.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              AppSpacing.hGapSm,
            ],
            Text(label, style: AppTypography.labelMedium.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.sort, required this.onChanged});

  final _Sort sort;
  final ValueChanged<_Sort> onChanged;

  String get _label => switch (sort) {
        _Sort.popularity => 'Popularity',
        _Sort.priceLow => 'Price: Low',
        _Sort.rating => 'Rating',
      };

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return PopupMenuButton<_Sort>(
      onSelected: onChanged,
      itemBuilder: (_) => const [
        PopupMenuItem(value: _Sort.popularity, child: Text('Popularity')),
        PopupMenuItem(value: _Sort.priceLow, child: Text('Price: Low to High')),
        PopupMenuItem(value: _Sort.rating, child: Text('Rating')),
      ],
      child: Row(
        children: [
          Text('Sort: ',
              style:
                  AppTypography.bodySmall.copyWith(color: vs.textSecondary)),
          Text(_label, style: AppTypography.labelMedium),
          Icon(Icons.keyboard_arrow_down_rounded,
              size: 18, color: vs.textSecondary),
        ],
      ),
    );
  }
}

class _FiltersPill extends StatelessWidget {
  const _FiltersPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: context.vsColors.brand,
        borderRadius: AppRadius.brPill,
        boxShadow: AppShadows.md,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.filter_list_rounded,
              size: 16, color: AppColors.white),
          AppSpacing.hGapSm,
          Text('$count Filter${count == 1 ? '' : 's'} Applied',
              style: AppTypography.labelMedium.copyWith(color: AppColors.white)),
        ],
      ),
    );
  }
}

/// Recent + trending suggestion chips, shown when the query is empty.
class _Suggestions extends ConsumerWidget {
  const _Suggestions({required this.onTerm});

  final ValueChanged<String> onTerm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    final recent = ref.watch(recentSearchesProvider);

    return ListView(
      padding: AppSpacing.screen,
      children: [
        if (recent.isNotEmpty) ...[
          Row(
            children: [
              Text('Recent Searches', style: AppTypography.titleMedium),
              const Spacer(),
              GestureDetector(
                onTap: () => ref.read(recentSearchesProvider.notifier).clear(),
                child: Text('Clear All',
                    style:
                        AppTypography.labelMedium.copyWith(color: vs.danger)),
              ),
            ],
          ),
          AppSpacing.vGapMd,
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final term in recent)
                _SuggestChip(
                  label: term,
                  icon: Icons.history_rounded,
                  onTap: () => onTerm(term),
                  onRemove: () =>
                      ref.read(recentSearchesProvider.notifier).remove(term),
                ),
            ],
          ),
          AppSpacing.vGapXl,
        ],
        Text('Trending', style: AppTypography.titleMedium),
        AppSpacing.vGapMd,
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final term in trendingSearches)
              _SuggestChip(
                label: term,
                icon: Icons.trending_up_rounded,
                onTap: () => onTerm(term),
              ),
          ],
        ),
      ],
    );
  }
}

class _SuggestChip extends StatelessWidget {
  const _SuggestChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.onRemove,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brPill,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: AppRadius.brPill,
          border: Border.all(color: vs.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: vs.textSecondary),
            AppSpacing.hGapSm,
            Text(label, style: AppTypography.bodyMedium),
            if (onRemove != null) ...[
              const SizedBox(width: AppSpacing.xs),
              GestureDetector(
                onTap: onRemove,
                child: Icon(Icons.close_rounded,
                    size: 14, color: vs.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
