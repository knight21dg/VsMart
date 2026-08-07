import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../cart/presentation/providers/cart_providers.dart';
import '../../../catalog/domain/entities/product.dart';
import '../../../catalog/presentation/category_icons.dart';
import '../../../catalog/presentation/product_navigation.dart';
import '../../../catalog/presentation/product_share.dart';
import '../../../catalog/presentation/providers/catalog_providers.dart';
import '../../../wishlist/presentation/providers/wishlist_providers.dart';
import '../providers/search_providers.dart';

// Sort by rating was removed: VS Mart groceries carry no product-rating data
// (feedback is captured per-order), so a "Rating" sort silently emptied results.
enum _Sort { popularity, priceLow }

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
  _Sort _sort = _Sort.popularity;

  @override
  void initState() {
    super.initState();
    // The query/input state providers are app-scoped, so a stale query from a
    // previous visit would mismatch this screen's fresh (empty) text field.
    // Open search clean — recent + trending — every time.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(searchInputProvider.notifier).state = '';
      ref.read(searchQueryProvider.notifier).state = '';
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Debounced live text → drives the as-you-type autocomplete.
  void _onInput(String value) =>
      ref.read(searchInputProvider.notifier).state = value.trim();

  /// Commit a query → run the full results grid.
  void _submit(String value) {
    final q = value.trim();
    if (q.isEmpty) return;
    ref.read(recentSearchesProvider.notifier).add(q);
    ref.read(searchInputProvider.notifier).state = q;
    ref.read(searchQueryProvider.notifier).state = q;
    context.hideKeyboard();
  }

  /// Run a term from a suggestion (fills the field, then commits).
  void _runTerm(String term) {
    _controller.text = term;
    _controller.selection = TextSelection.collapsed(offset: term.length);
    _submit(term);
  }

  /// Insert a completion term into the field WITHOUT committing, so the user can
  /// keep refining (the ↖ affordance on a suggestion row).
  void _fillTerm(String term) {
    _controller.text = term;
    _controller.selection = TextSelection.collapsed(offset: term.length);
    _onInput(term);
  }

  /// Advanced-filters bottom sheet: tune the quick filters + sort order.
  Future<void> _openFilters() async {
    var underPrice = _underPrice;
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
              Text(ctx.l10n.searchFiltersAndSort,
                  style: AppTypography.titleLarge),
              AppSpacing.vGapMd,
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(ctx.l10n.searchUnderPrice),
                value: underPrice,
                onChanged: (v) => setSheet(() => underPrice = v),
              ),
              const Divider(),
              Text(ctx.l10n.catalogSortBy, style: AppTypography.titleMedium),
              for (final option in _Sort.values)
                RadioListTile<_Sort>(
                  contentPadding: EdgeInsets.zero,
                  title: Text(switch (option) {
                    _Sort.popularity => ctx.l10n.searchPopularity,
                    _Sort.priceLow => ctx.l10n.searchPriceLowHigh,
                  }),
                  value: option,
                  groupValue: sort,
                  onChanged: (v) => setSheet(() => sort = v!),
                ),
              AppSpacing.vGapMd,
              SizedBox(
                width: double.infinity,
                child: VSButton(
                  label: ctx.l10n.catalogApplyFilters,
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
        _sort = sort;
      });
    }
  }

  List<Product> _apply(List<Product> input) {
    var list = input.where((p) {
      if (_underPrice && p.price >= 99) return false;
      return true;
    }).toList();
    switch (_sort) {
      case _Sort.popularity:
        list.sort((a, b) => b.reviews.compareTo(a.reviews));
      case _Sort.priceLow:
        list.sort((a, b) => a.price.compareTo(b.price));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final committed = ref.watch(searchQueryProvider);
    final input = ref.watch(searchInputProvider);
    // Results are shown only once a query is committed AND the field still holds
    // exactly that query; the moment the user edits, we drop back to live
    // suggestions (Blinkit/Zepto behaviour).
    final showResults = committed.isNotEmpty && committed == input;

    final Widget body;
    if (showResults) {
      body = _results(committed);
    } else if (input.isNotEmpty) {
      body = _LiveSuggestions(
        query: input,
        onTerm: _runTerm,
        onFill: _fillTerm,
      );
    } else {
      body = _Suggestions(onTerm: _runTerm);
    }

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
          hint: context.l10n.searchHint,
          onChanged: _onInput,
          onSubmitted: _submit,
        ),
      ),
      body: SafeArea(top: false, child: body),
    );
  }

  Widget _results(String query) {
    final async = ref.watch(searchProductsProvider(query));
    final activeFilters = (_underPrice ? 1 : 0);

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
                  onUnderPrice: () =>
                      setState(() => _underPrice = !_underPrice),
                  onFilters: _openFilters,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.sm),
                  child: Row(
                    children: [
                      Text(context.l10n.searchResultsFound(products.length),
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
                          title: context.l10n.searchNoResults,
                          message: context.l10n.searchNoResultsFor(query),
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
      price: p.displayPrice,
      mrp: p.displayMrp,
      imageUrl: p.imageUrl,
      outOfStock: !p.effectiveInStock,
      inWishlist: wishlisted,
      quantityInCart: qty,
      heroTag: detailHeroTag('search', p.id),
      onWishlistTap: () => ref.read(wishlistProvider.notifier).toggle(p.id),
      onShareTap: () => shareProductLink(context, ref, p),
      onTap: () =>
          openProductDetail(context, productId: p.id, source: 'search'),
      onAdd: () => addToCartOrChoose(context, ref, p, source: 'search'),
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
    required this.onUnderPrice,
    required this.onFilters,
  });

  final bool underPrice;
  final VoidCallback onUnderPrice;
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
            label: context.l10n.catalogFilters,
            icon: Icons.tune_rounded,
            selected: false,
            onTap: onFilters,
          ),
          AppSpacing.hGapSm,
          _Chip(
            label: context.l10n.searchUnderPrice,
            selected: underPrice,
            onTap: onUnderPrice,
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

  String _label(BuildContext context) => switch (sort) {
        _Sort.popularity => context.l10n.searchPopularity,
        _Sort.priceLow => context.l10n.searchPriceLowHigh,
      };

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return PopupMenuButton<_Sort>(
      onSelected: onChanged,
      itemBuilder: (_) => [
        PopupMenuItem(
            value: _Sort.popularity,
            child: Text(context.l10n.searchPopularity)),
        PopupMenuItem(
            value: _Sort.priceLow,
            child: Text(context.l10n.searchPriceLowHigh)),
      ],
      child: Row(
        children: [
          Text(context.l10n.searchSortPrefix,
              style:
                  AppTypography.bodySmall.copyWith(color: vs.textSecondary)),
          Text(_label(context), style: AppTypography.labelMedium),
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
          Text(context.l10n.searchFiltersApplied(count),
              style: AppTypography.labelMedium.copyWith(color: AppColors.white)),
        ],
      ),
    );
  }
}

/// As-you-type autocomplete: a "search for" row, completion terms, matching
/// categories and top product matches — shown while typing, before a query is
/// committed. Backed by the lightweight `/products/suggest` endpoint.
class _LiveSuggestions extends ConsumerWidget {
  const _LiveSuggestions({
    required this.query,
    required this.onTerm,
    required this.onFill,
  });

  final String query;

  /// Run a full search for the given term.
  final ValueChanged<String> onTerm;

  /// Insert the term into the field without committing (refine).
  final ValueChanged<String> onFill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(searchSuggestionsProvider(query));
    final ql = query.toLowerCase();

    final results = async.when(
      loading: () => const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: LinearProgressIndicator(minHeight: 2),
        ),
      ],
      // A failed autocomplete is non-blocking: the user can still submit via the
      // "search for" row above.
      error: (_, __) => const <Widget>[],
      data: (s) => [
        for (final term in s.terms.where((t) => t.toLowerCase() != ql))
          _TermRow(
            term: term,
            query: query,
            onTap: () => onTerm(term),
            onFill: () => onFill(term),
          ),
        if (s.categories.isNotEmpty) ...[
          _SectionLabel(context.l10n.navCategories),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final cat in s.categories)
                  _SuggestChip(
                    label: cat.name,
                    // The category's own artwork, then its data-driven icon —
                    // every chip used to show the same generic placeholder.
                    imageUrl: cat.imageUrl,
                    icon: categoryIcon(cat.iconName),
                    onTap: () => onTerm(cat.name),
                  ),
              ],
            ),
          ),
        ],
        if (s.products.isNotEmpty) ...[
          _SectionLabel(context.l10n.catalogProducts),
          for (final p in s.products) _ProductSuggestionRow(product: p),
        ],
      ],
    );

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: AppSpacing.huge),
      children: [
        _SearchForRow(query: query, onTap: () => onTerm(query)),
        const Divider(height: 1),
        ...results,
      ],
    );
  }
}

/// The always-present first row of the autocomplete — runs the full search for
/// whatever is currently typed, so the user can submit even before (or without)
/// suggestions loading.
class _SearchForRow extends StatelessWidget {
  const _SearchForRow({required this.query, required this.onTap});

  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return ListTile(
      onTap: onTap,
      leading: Icon(Icons.search_rounded, color: vs.brand),
      title: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: context.l10n.searchForPrefix,
              style:
                  AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
            ),
            TextSpan(
              text: '"$query"',
              style: AppTypography.bodyMedium
                  .copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      trailing:
          Icon(Icons.arrow_forward_rounded, size: 18, color: vs.textSecondary),
    );
  }
}

/// A completion-term row: tap runs the search; the ↖ affordance inserts it into
/// the field for refinement. The typed portion is de-emphasised so the
/// completion stands out.
class _TermRow extends StatelessWidget {
  const _TermRow({
    required this.term,
    required this.query,
    required this.onTap,
    required this.onFill,
  });

  final String term;
  final String query;
  final VoidCallback onTap;
  final VoidCallback onFill;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final base = AppTypography.bodyMedium;
    final strong = base.copyWith(fontWeight: FontWeight.w700);
    final idx = term.toLowerCase().indexOf(query.toLowerCase());

    final Widget title = (idx < 0 || query.isEmpty)
        ? Text(term, maxLines: 1, overflow: TextOverflow.ellipsis, style: base)
        : Text.rich(
            TextSpan(children: [
              TextSpan(text: term.substring(0, idx), style: strong),
              TextSpan(
                  text: term.substring(idx, idx + query.length), style: base),
              TextSpan(text: term.substring(idx + query.length), style: strong),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );

    return ListTile(
      dense: true,
      onTap: onTap,
      leading: Icon(Icons.search_rounded, size: 20, color: vs.textSecondary),
      title: title,
      trailing: IconButton(
        icon:
            Icon(Icons.north_west_rounded, size: 18, color: vs.textSecondary),
        onPressed: onFill,
        tooltip: MaterialLocalizations.of(context).searchFieldLabel,
      ),
    );
  }
}

/// A product match in the autocomplete list — thumbnail, name, brand, price;
/// tapping opens the product detail.
class _ProductSuggestionRow extends StatelessWidget {
  const _ProductSuggestionRow({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final p = product;
    return ListTile(
      onTap: () =>
          openProductDetail(context, productId: p.id, source: 'search-suggest'),
      leading: VSNetworkImage(url: p.imageUrl, width: 44, height: 44),
      title: Text(p.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodyMedium),
      subtitle: p.brand.isEmpty
          ? null
          : Text(p.brand,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall
                  .copyWith(color: vs.textSecondary)),
      trailing: Text(p.price.asCurrency, style: AppTypography.priceMedium),
    );
  }
}

/// Small section heading used inside the autocomplete list.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
      child: Text(text,
          style: AppTypography.labelMedium
              .copyWith(color: context.vsColors.textSecondary)),
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
              Text(context.l10n.searchRecent,
                  style: AppTypography.titleMedium),
              const Spacer(),
              GestureDetector(
                onTap: () => ref.read(recentSearchesProvider.notifier).clear(),
                child: Text(context.l10n.commonClearAll,
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
        Text(context.l10n.searchPopular, style: AppTypography.titleMedium),
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
    this.imageUrl,
    this.onRemove,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  /// Optional thumbnail shown in place of [icon] (category chips).
  final String? imageUrl;
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
            if (imageUrl != null && imageUrl!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: VSNetworkImage(
                    url: imageUrl, width: 18, height: 18, fit: BoxFit.cover),
              )
            else
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
