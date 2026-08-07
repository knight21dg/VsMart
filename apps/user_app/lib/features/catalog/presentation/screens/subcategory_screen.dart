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
import '../product_share.dart';
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
            // The department itself, looked up for its artwork. Passing
            // `departmentId` here (a numeric pk) meant categoryIcon() never
            // matched a token and every banner showed the same generic icon.
            _Banner(
              name: departmentName,
              department: ref.watch(departmentsProvider).maybeWhen(
                    data: (depts) => depts
                        .where((d) => d.id == departmentId)
                        .cast<Category?>()
                        .firstOrNull,
                    orElse: () => null,
                  ),
            ),
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
                    Text(context.l10n.homeShopByCategory,
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
                                'departmentId': departmentId,
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
          return VSEmptyState(
            title: context.l10n.catalogNoProducts,
            message: context.l10n.catalogNoProductsInCategory,
            icon: Icons.inventory_2_outlined,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(context.l10n.catalogProducts,
                    style: AppTypography.titleLarge),
                const Spacer(),
                Text(context.l10n.cartItemsCount(products.length),
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
      price: p.displayPrice,
      mrp: p.displayMrp,
      imageUrl: p.imageUrl,
      outOfStock: !p.effectiveInStock,
      inWishlist: wishlisted,
      quantityInCart: qty,
      heroTag: detailHeroTag('subcat', p.id),
      onWishlistTap: () => ref.read(wishlistProvider.notifier).toggle(p.id),
      onShareTap: () => shareProductLink(context, ref, p),
      onTap: () =>
          openProductDetail(context, productId: p.id, source: 'subcat'),
      onAdd: () => addToCartOrChoose(context, ref, p, source: 'subcat'),
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
          child: Text(context.l10n.navCategories,
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
  const _Banner({required this.name, this.department});

  final String name;

  /// The department this banner heads, when it has loaded — supplies the image
  /// and the icon token. Null while departments are still loading, which just
  /// falls back to the generic icon.
  final Category? department;

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
                Text(context.l10n.catalogFreshPicksIn,
                    style:
                        AppTypography.labelMedium.copyWith(color: vs.brand)),
                const SizedBox(height: 2),
                Text(name, style: AppTypography.headlineSmall),
                const SizedBox(height: 2),
                Text(context.l10n.catalogHandpickedQuality,
                    style: AppTypography.bodySmall
                        .copyWith(color: vs.textSecondary)),
              ],
            ),
          ),
          _BannerArt(department: department),
        ],
      ),
    );
  }
}

/// The banner's 56px badge: the department's image when it has one, else its
/// data-driven icon.
class _BannerArt extends StatelessWidget {
  const _BannerArt({required this.department});

  final Category? department;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final img = department?.imageUrl;
    return Container(
      height: 56,
      width: 56,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
          color: context.colors.surface, shape: BoxShape.circle),
      child: (img != null && img.isNotEmpty)
          ? VSNetworkImage(url: img, width: 56, height: 56, fit: BoxFit.cover)
          : Icon(categoryIcon(department?.iconName), color: vs.brand, size: 30),
    );
  }
}
