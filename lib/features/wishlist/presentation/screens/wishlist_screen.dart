import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../cart/presentation/providers/cart_providers.dart';
import '../../../catalog/domain/entities/product.dart';
import '../../../catalog/presentation/product_navigation.dart';
import '../providers/wishlist_providers.dart';

enum _WishFilter { all, inStock, priceDrop }

/// Enhanced Wishlist — matches the design: brand header, value summary card,
/// filter tabs, and rich list cards (image + badge, details, Add / Buy Now).
class WishlistScreen extends ConsumerStatefulWidget {
  const WishlistScreen({super.key});

  @override
  ConsumerState<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends ConsumerState<WishlistScreen> {
  _WishFilter _filter = _WishFilter.all;

  List<Product> _apply(List<Product> items) => switch (_filter) {
        _WishFilter.all => items,
        _WishFilter.inStock => items.where((p) => p.inStock).toList(),
        _WishFilter.priceDrop =>
          items.where((p) => p.discountPercent > 0).toList(),
      };

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final async = ref.watch(wishlistProductsProvider);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text('VS Mart',
            style: AppTypography.headlineSmall.copyWith(color: vs.brand)),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () => context.pushNamed(RouteNames.search),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: async.when(
          loading: () => const VSLoadingView(),
          error: (e, _) => VSErrorView(
            failure: e is Failure ? e : null,
            onRetry: () => ref.invalidate(wishlistProductsProvider),
          ),
          data: (items) {
            if (items.isEmpty) {
              return VSEmptyState(
                title: 'Your wishlist is empty',
                message: 'Tap the heart on any product to save it for later.',
                icon: Icons.favorite_border_rounded,
                actionLabel: 'Browse Products',
                onAction: () => context.pushNamed(RouteNames.products),
              );
            }
            final shown = _apply(items);
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxl),
              children: [
                Text('Wishlist', style: AppTypography.headlineMedium),
                AppSpacing.vGapMd,
                _SummaryCard(items: items),
                AppSpacing.vGapLg,
                _FilterTabs(
                  filter: _filter,
                  onChanged: (f) => setState(() => _filter = f),
                ),
                AppSpacing.vGapLg,
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    child: Center(
                      child: Text('Nothing matches this filter.',
                          style: AppTypography.bodyMedium
                              .copyWith(color: vs.textSecondary)),
                    ),
                  )
                else
                  for (final p in shown)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _WishlistCard(product: p),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.items});

  final List<Product> items;

  @override
  Widget build(BuildContext context) {
    final faint = AppColors.white.withValues(alpha: 0.85);
    final total = items.fold<num>(0, (sum, p) => sum + p.price);
    final drops = items.where((p) => p.discountPercent > 0).length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: const BoxDecoration(
        gradient: AppColors.greenGradient,
        borderRadius: AppRadius.brXl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Total Value of Wishlist',
              style: AppTypography.bodySmall.copyWith(color: faint)),
          AppSpacing.vGapXs,
          Text(total.asCurrency,
              style:
                  AppTypography.displayMedium.copyWith(color: AppColors.white)),
          AppSpacing.vGapLg,
          Row(
            children: [
              Expanded(
                child: _Stat(
                    label: 'Saved Items', value: '${items.length}', faint: faint),
              ),
              Expanded(
                child: _Stat(
                    label: 'Price Drop Alerts',
                    value: '$drops',
                    faint: faint),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(
      {required this.label, required this.value, required this.faint});

  final String label;
  final String value;
  final Color faint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.bodySmall.copyWith(color: faint)),
        Text(value,
            style: AppTypography.headlineSmall.copyWith(color: AppColors.white)),
      ],
    );
  }
}

class _FilterTabs extends StatelessWidget {
  const _FilterTabs({required this.filter, required this.onChanged});

  final _WishFilter filter;
  final ValueChanged<_WishFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final tabs = <(_WishFilter, String, IconData?)>[
      (_WishFilter.all, 'All Items', null),
      (_WishFilter.inStock, 'In Stock', null),
      (_WishFilter.priceDrop, 'Price Drop', Icons.trending_down_rounded),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (value, label, icon) in tabs)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: _Tab(
                label: label,
                icon: icon,
                selected: filter == value,
                onTap: () => onChanged(value),
              ),
            ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
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
    final fg = selected ? AppColors.white : context.colors.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brPill,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected ? vs.brand : context.colors.surface,
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

class _WishlistCard extends ConsumerWidget {
  const _WishlistCard({required this.product});

  final Product product;

  void _add(BuildContext context, WidgetRef ref) {
    HapticFeedback.mediumImpact();
    ref.read(cartControllerProvider.notifier).addProduct(product);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    final p = product;
    final discount = p.discountPercent;
    final heroTag = detailHeroTag('wishlist', p.id);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Hero(
                    tag: heroTag,
                    flightShuttleBuilder: (_, __, ___, ____, _____) =>
                        VSNetworkImage(
                      url: p.imageUrl,
                      fit: BoxFit.cover,
                      borderRadius: AppRadius.brMd,
                    ),
                    child: VSNetworkImage(
                      url: p.imageUrl,
                      width: 76,
                      height: 76,
                      borderRadius: AppRadius.brMd,
                    ),
                  ),
                  if (discount > 0)
                    Positioned(
                      top: 0,
                      left: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm, vertical: 2),
                        decoration: BoxDecoration(
                          color: vs.offer,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(AppRadius.md),
                            bottomRight: Radius.circular(AppRadius.sm),
                          ),
                        ),
                        child: Text('$discount% OFF',
                            style: AppTypography.labelSmall
                                .copyWith(color: AppColors.white)),
                      ),
                    ),
                ],
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.brand,
                        style: AppTypography.bodySmall
                            .copyWith(color: vs.textSecondary)),
                    Text(p.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.titleMedium),
                    Text(p.unit,
                        style: AppTypography.bodySmall
                            .copyWith(color: vs.textSecondary)),
                    AppSpacing.vGapXs,
                    Row(
                      children: [
                        Text(p.price.asCurrency,
                            style: AppTypography.priceMedium),
                        if (discount > 0) ...[
                          AppSpacing.hGapSm,
                          Text(p.mrp.asCurrency,
                              style: AppTypography.bodySmall.copyWith(
                                color: vs.textSecondary,
                                decoration: TextDecoration.lineThrough,
                              )),
                          AppSpacing.hGapSm,
                          Text('$discount% OFF',
                              style: AppTypography.labelSmall
                                  .copyWith(color: vs.offer)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              _Menu(
                onRemove: () {
                  ref.read(wishlistProvider.notifier).remove(p.id);
                  context.showSnack('${p.name} removed from wishlist');
                },
                onView: () => context.pushNamed(
                  RouteNames.productDetails,
                  pathParameters: {'productId': p.id},
                  extra: heroTag,
                ),
              ),
            ],
          ),
          AppSpacing.vGapMd,
          Row(
            children: [
              Expanded(
                child: VSButton(
                  label: 'Add',
                  icon: Icons.shopping_cart_outlined,
                  size: VSButtonSize.medium,
                  onPressed: p.inStock ? () => _add(context, ref) : null,
                ),
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: VSOutlinedButton(
                  label: 'Buy Now',
                  onPressed: p.inStock
                      ? () {
                          _add(context, ref);
                          context.pushNamed(RouteNames.checkout);
                        }
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu({required this.onRemove, required this.onView});

  final VoidCallback onRemove;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      icon: Icon(Icons.more_vert_rounded, color: context.vsColors.textSecondary),
      onSelected: (v) => v == 0 ? onView() : onRemove(),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 0, child: Text('View product')),
        PopupMenuItem(value: 1, child: Text('Remove')),
      ],
    );
  }
}
