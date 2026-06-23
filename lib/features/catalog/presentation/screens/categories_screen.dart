import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../cart/presentation/providers/cart_providers.dart';
import '../../domain/entities/category.dart';
import '../category_icons.dart';
import '../providers/catalog_providers.dart';
import '../widgets/cart_summary_bar.dart';

/// Categories tab: a department rail on the left (from [departmentsProvider]) and
/// a grid of sub-categories on the right (from [categoriesProvider]).
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  String? _selectedDept;
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openListing(Category category) => context.pushNamed(
        RouteNames.products,
        queryParameters: {'categoryId': category.id, 'title': category.name},
      );

  @override
  Widget build(BuildContext context) {
    final departments = ref.watch(departmentsProvider);
    final categories = ref.watch(categoriesProvider(null));
    final cart = ref.watch(cartControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 104,
                  child: departments.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (items) => _DepartmentRail(
                      items: items,
                      selectedId: _selectedDept ??
                          (items.isNotEmpty ? items.first.id : null),
                      onSelect: (id) => setState(() => _selectedDept = id),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.md,
                            AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
                        child: VSSearchField(
                          controller: _searchController,
                          hint: 'Search categories…',
                          onChanged: (v) =>
                              setState(() => _query = v.trim().toLowerCase()),
                          onSubmitted: (v) {
                            // Hand a non-matching free-text query off to the
                            // full product search.
                            if (v.trim().isNotEmpty) {
                              context.pushNamed(RouteNames.search);
                            }
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            AppSpacing.md, 0, AppSpacing.lg, AppSpacing.sm),
                        child: Text(
                            _query.isEmpty
                                ? 'All Categories'
                                : 'Results for "$_query"',
                            style: AppTypography.titleLarge),
                      ),
                      Expanded(
                        child: categories.when(
                          loading: () => const VSLoadingView(),
                          error: (e, _) => VSErrorView(
                            failure: e is Failure ? e : null,
                            onRetry: () =>
                                ref.invalidate(categoriesProvider(null)),
                          ),
                          data: (all) {
                            final results = _scoped(all);
                            if (results.isEmpty) {
                              return VSEmptyState(
                                icon: Icons.search_off_rounded,
                                title: 'No categories found',
                                message:
                                    'No categories match "$_query". Try a different term.',
                                actionLabel: 'Search all products',
                                onAction: () =>
                                    context.pushNamed(RouteNames.search),
                              );
                            }
                            return _CategoryGrid(
                              categories: results,
                              onTap: _openListing,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
    );
  }

  /// Resolves the visible categories: a free-text [_query] searches across every
  /// department; otherwise the grid is scoped to the selected department.
  List<Category> _scoped(List<Category> all) {
    if (_query.isNotEmpty) {
      return all
          .where((c) => c.name.toLowerCase().contains(_query))
          .toList();
    }
    if (_selectedDept == null) return all;
    final scoped = all.where((c) => c.parentId == _selectedDept).toList();
    return scoped.isEmpty ? all : scoped;
  }
}

class _DepartmentRail extends StatelessWidget {
  const _DepartmentRail({
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
          final dept = items[i];
          final active = dept.id == selectedId;
          return InkWell(
            onTap: () => onSelect(dept.id),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
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
                  Icon(categoryIcon(dept.iconName),
                      color: active ? vs.brand : vs.textSecondary, size: 24),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    dept.name,
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

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.categories, required this.onTap});

  final List<Category> categories;
  final ValueChanged<Category> onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, 0, AppSpacing.lg, 96),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
        childAspectRatio: 0.72,
      ),
      itemCount: categories.length,
      itemBuilder: (_, i) => _CategoryTile(
        category: categories[i],
        onTap: () => onTap(categories[i]),
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
            Container(
              height: 48,
              width: 48,
              decoration:
                  BoxDecoration(color: vs.brandTint, shape: BoxShape.circle),
              child: Icon(categoryIcon(category.iconName),
                  color: vs.brand, size: 24),
            ),
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
