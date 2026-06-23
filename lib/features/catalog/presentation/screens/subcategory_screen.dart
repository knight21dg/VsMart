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
import '../widgets/vs_subcategory_card.dart';

/// Category → Sub-Category drill-down. Shows a breadcrumb, a department banner,
/// and the grid of sub-categories; tapping one opens its product listing.
class SubCategoryScreen extends ConsumerWidget {
  const SubCategoryScreen({
    super.key,
    required this.departmentId,
    required this.departmentName,
  });

  final String departmentId;
  final String departmentName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subCategories = ref.watch(subCategoriesProvider(departmentId));

    return Scaffold(
      appBar: AppBar(
        title: Text(departmentName),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () => context.pushNamed(RouteNames.search),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(subCategoriesProvider(departmentId)),
        child: ListView(
          padding: AppSpacing.screen,
          children: [
            _Breadcrumb(department: departmentName),
            AppSpacing.vGapMd,
            _Banner(name: departmentName, iconName: departmentId),
            AppSpacing.vGapLg,
            subCategories.when(
              loading: () => const Padding(
                padding: EdgeInsets.only(top: AppSpacing.huge),
                child: VSLoadingView(),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xl),
                child: VSErrorView(
                  failure: e is Failure ? e : null,
                  onRetry: () =>
                      ref.invalidate(subCategoriesProvider(departmentId)),
                ),
              ),
              data: (items) {
                // No sub-categories → show this department's products inline.
                if (items.isEmpty) {
                  return _DepartmentProducts(departmentId: departmentId);
                }
                // Otherwise show the sub-category grid.
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Shop by Category',
                        style: AppTypography.titleLarge),
                    AppSpacing.vGapMd,
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: AppSpacing.md,
                        crossAxisSpacing: AppSpacing.md,
                        childAspectRatio: 0.78,
                      ),
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final Category c = items[i];
                        return VSSubCategoryCard(
                          name: c.name,
                          productCount: c.productCount,
                          icon: categoryIcon(c.iconName),
                          imageUrl: c.imageUrl,
                          onTap: () {
                            ref.read(analyticsServiceProvider).track(
                                'subcategory_opened', {'subcategory': c.id});
                            context.pushNamed(
                              RouteNames.products,
                              queryParameters: {
                                'categoryId': c.id,
                                'title': c.name
                              },
                            );
                          },
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows a department's products directly when it has no sub-categories.
class _DepartmentProducts extends ConsumerWidget {
  const _DepartmentProducts({required this.departmentId});

  final String departmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    final async = ref.watch(productsProvider(departmentId));
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(top: AppSpacing.huge),
        child: VSLoadingView(),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xl),
        child: VSErrorView(
          failure: e is Failure ? e : null,
          onRetry: () => ref.invalidate(productsProvider(departmentId)),
        ),
      ),
      data: (products) {
        if (products.isEmpty) {
          return const VSEmptyState(
            title: 'No products',
            message: 'There are no products in this category yet.',
            icon: Icons.inventory_2_outlined,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Products', style: AppTypography.titleLarge),
                const Spacer(),
                Text('${products.length} items',
                    style: AppTypography.labelMedium
                        .copyWith(color: vs.textSecondary)),
              ],
            ),
            AppSpacing.vGapMd,
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: AppSpacing.md,
                crossAxisSpacing: AppSpacing.md,
                childAspectRatio: 0.62,
              ),
              itemCount: products.length,
              itemBuilder: (_, i) =>
                  _ProductCell(products: products, index: i),
            ),
          ],
        );
      },
    );
  }
}

class _ProductCell extends ConsumerWidget {
  const _ProductCell({required this.products, required this.index});

  final List<Product> products;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = products[index];
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
      heroTag: detailHeroTag('subcat', p.id),
      onWishlistTap: () => ref.read(wishlistProvider.notifier).toggle(p.id),
      onTap: () =>
          openProductDetail(context, productId: p.id, source: 'subcat'),
      onAdd: () => ref.read(cartControllerProvider.notifier).addProduct(p),
      onIncrement: () =>
          ref.read(cartControllerProvider.notifier).increment(p.id),
      onDecrement: () =>
          ref.read(cartControllerProvider.notifier).decrement(p.id),
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.department});

  final String department;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Row(
      children: [
        GestureDetector(
          onTap: () => context.goNamed(RouteNames.categories),
          child: Text('Categories',
              style: AppTypography.bodySmall.copyWith(color: vs.trust)),
        ),
        Icon(Icons.chevron_right_rounded, size: 16, color: vs.textSecondary),
        Text(department,
            style: AppTypography.bodySmall.copyWith(color: vs.textSecondary)),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.name, required this.iconName});

  final String name;
  final String iconName;

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
                Text('Fresh picks in',
                    style:
                        AppTypography.labelMedium.copyWith(color: vs.brand)),
                const SizedBox(height: 2),
                Text(name, style: AppTypography.headlineSmall),
                const SizedBox(height: 2),
                Text('Handpicked, quality-checked, delivered fast',
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
            child: Icon(categoryIcon(iconName), color: vs.brand, size: 30),
          ),
        ],
      ),
    );
  }
}
