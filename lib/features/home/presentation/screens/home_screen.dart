import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../billing/presentation/providers/billing_providers.dart';
import '../../../billing/presentation/widgets/credit_due_banner.dart';
import '../../../address/domain/entities/address.dart';
import '../../../address/presentation/providers/address_providers.dart';
import '../../../cart/presentation/providers/cart_providers.dart';
import '../../../catalog/domain/entities/category.dart';
import '../../../catalog/domain/entities/product.dart';
import '../../../catalog/presentation/category_icons.dart';
import '../../../catalog/presentation/product_navigation.dart';
import '../../../catalog/presentation/providers/catalog_providers.dart';
import '../../../catalog/presentation/providers/recently_viewed_provider.dart';
import '../../../credit/presentation/providers/credit_providers.dart';
import '../../../location/presentation/providers/location_providers.dart';
import '../../../offers/domain/entities/offer.dart';
import '../../../offers/presentation/providers/offer_providers.dart';
import '../../../offers/presentation/widgets/vs_offer_banner.dart';
import '../../../orders/domain/entities/order_enums.dart';
import '../../../orders/presentation/providers/order_providers.dart';
import '../../../orders/presentation/widgets/order_widgets.dart';
import '../../../serviceability/presentation/widgets/serviceability_banner.dart';
import '../widgets/vs_home_shimmer.dart';

/// VS Mart home dashboard: location header, search, credit summary, an offer
/// carousel, quick actions, deals, categories, and product rails. Cached +
/// pull-to-refresh + offline-aware.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with SingleTickerProviderStateMixin {
  late final ScrollController _scrollController;
  double _scrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(analyticsServiceProvider).track('home_viewed');
      // Resolve the live device location for the "Delivery to <area>" header.
      ref.read(locationControllerProvider.notifier).ensureResolved();
      _maybeAutoDetectLocation();
    });
  }

  /// On first launch (no saved address yet) try to fetch the device location
  /// automatically and use it as the delivery address.
  Future<void> _maybeAutoDetectLocation() async {
    if (ref.read(addressesProvider).isNotEmpty) return;
    await ref.read(addressesProvider.notifier).detectAndSetLocation();
  }

  void _onScroll() {
    setState(() {
      _scrollOffset = _scrollController.offset;
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref
      ..invalidate(bannersProvider)
      ..invalidate(dealsProvider)
      ..invalidate(departmentsProvider)
      ..invalidate(popularProductsProvider)
      ..invalidate(recommendedProductsProvider)
      ..invalidate(productsProvider(null))
      ..invalidate(creditAccountProvider)
      ..invalidate(currentStatementProvider);
    await ref.read(departmentsProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final connectivity = ref.watch(commerceConnectivityProvider);
    final departments = ref.watch(departmentsProvider);
    final recentlyViewed =
        ref.watch(recentlyViewedProductsProvider).valueOrNull ?? const [];
    final recentlyOrdered =
        ref.watch(recentlyOrderedProductsProvider).valueOrNull ?? const [];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            VSOfflineBanner(
              offline: connectivity == CommerceConnectivity.offline,
              syncing: connectivity == CommerceConnectivity.syncing,
            ),
            Expanded(
              child: departments.isLoading && !departments.hasValue
                  ? const VSHomeShimmer()
                  : (departments.hasError && !departments.hasValue)
                  ? VSErrorView(onRetry: _refresh)
                  : RefreshIndicator(
                      onRefresh: _refresh,
                      child: CustomScrollView(
                        controller: _scrollController,
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                                  AppSpacing.sm, AppSpacing.lg, AppSpacing.xs),
                              child: _HomeHeader(scrollOffset: _scrollOffset),
                            ),
                          ),
                          const SliverToBoxAdapter(child: ServiceabilityBanner()),
                          SliverPersistentHeader(
                            pinned: true,
                            delegate: _SearchHeaderDelegate(
                              onTap: () => context.pushNamed(RouteNames.search),
                            ),
                          ),
                          SliverList(
                            delegate: SliverChildListDelegate([
                          AppSpacing.vGapMd,
                          const _OfferCarousel(),
                          AppSpacing.vGapLg,
                          const CreditDueBanner(),
                          AppSpacing.vGapMd,
                          const _OrderStatusCard(),
                          AppSpacing.vGapMd,
                          const Padding(
                            padding: AppSpacing.screenHorizontal,
                            child: _QuickActions(),
                          ),
                          AppSpacing.vGapXl,
                          const _TodaysDeals(),
                          AppSpacing.vGapXl,
                          const _SpotlightSection(),
                          AppSpacing.vGapXl,
                          Padding(
                            padding: AppSpacing.screenHorizontal,
                            child: _SectionHeader(
                              title: 'Explore Categories',
                              onSeeAll: () =>
                                  context.goNamed(RouteNames.categories),
                            ),
                          ),
                          AppSpacing.vGapMd,
                          const _CategoryRail(),
                          AppSpacing.vGapXl,
                          const _OfferCarousel(
                            placement: BannerPlacement.middle,
                            compact: true,
                          ),
                          AppSpacing.vGapXl,
                          Padding(
                            padding: AppSpacing.screenHorizontal,
                            child: _SectionHeader(
                              title: 'Popular Products',
                              onSeeAll: () =>
                                  context.pushNamed(RouteNames.popularProducts),
                            ),
                          ),
                          AppSpacing.vGapMd,
                          _ProductRail(
                              provider: popularProductsProvider,
                              source: 'home-pop'),
                          AppSpacing.vGapXl,
                          Padding(
                            padding: AppSpacing.screenHorizontal,
                            child: _SectionHeader(
                              title: 'Recommended for You',
                              onSeeAll: () =>
                                  context.pushNamed(RouteNames.recommendedProducts),
                            ),
                          ),
                          AppSpacing.vGapMd,
                          _ProductRail(
                              provider: recommendedProductsProvider,
                              source: 'home-rec'),
                          if (recentlyOrdered.isNotEmpty) ...[
                            AppSpacing.vGapXl,
                            Padding(
                              padding: AppSpacing.screenHorizontal,
                              child: _SectionHeader(
                                title: 'Recently Ordered',
                                onSeeAll: () =>
                                    context.pushNamed(RouteNames.recentlyOrdered),
                              ),
                            ),
                            AppSpacing.vGapMd,
                            _ProductRail(
                                provider: recentlyOrderedProductsProvider,
                                source: 'home-recent'),
                          ],
                          if (recentlyViewed.isNotEmpty) ...[
                            AppSpacing.vGapXl,
                            const Padding(
                              padding: AppSpacing.screenHorizontal,
                              child: _SectionHeader(title: 'Continue Shopping'),
                            ),
                            AppSpacing.vGapMd,
                            _ProductRail(
                                provider: recentlyViewedProductsProvider,
                                source: 'home-cont'),
                          ],
                          AppSpacing.vGapMd,
                          const VSLoveFooter(),
                            ]),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Surfaces the latest active order on Home with a Track CTA. Self-hides when
/// there is no active order.
class _OrderStatusCard extends ConsumerWidget {
  const _OrderStatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    final orders = ref.watch(ordersProvider).valueOrNull ?? const [];
    final active = orders.where((o) => o.status.isActive).toList();
    if (active.isEmpty) return const SizedBox.shrink();
    final order = active.first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
      child: InkWell(
        onTap: () => context.pushNamed(
          RouteNames.orderTracking,
          pathParameters: {'orderId': order.id},
        ),
        borderRadius: AppRadius.brLg,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: vs.trustTint,
            borderRadius: AppRadius.brLg,
          ),
          child: Row(
            children: [
              Icon(Icons.local_shipping_rounded, color: vs.trust),
              AppSpacing.hGapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Order #${order.id}',
                        style: AppTypography.titleMedium),
                    Text('Tap to track your order',
                        style: AppTypography.bodySmall
                            .copyWith(color: vs.textSecondary)),
                  ],
                ),
              ),
              VSOrderStatusChip(status: order.status, dense: true),
              AppSpacing.hGapSm,
              Icon(Icons.chevron_right_rounded, color: vs.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pinned search bar that sticks to the top once the location header scrolls
/// past it — the Blinkit-style sticky search.
class _SearchHeaderDelegate extends SliverPersistentHeaderDelegate {
  _SearchHeaderDelegate({required this.onTap});

  final VoidCallback onTap;

  static const double _height = 72;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: overlapsContent ? AppShadows.sm : null,
      ),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
      child: VSSearchField(
        readOnly: true,
        hint: 'Search for groceries, staples…',
        onTap: onTap,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SearchHeaderDelegate oldDelegate) => false;
}

class _HomeHeader extends ConsumerWidget {
  const _HomeHeader({required this.scrollOffset});

  final double scrollOffset;

  /// Fallback label from the saved default address when no live location yet.
  String _addressLabel(Address? a) {
    if (a == null) return '';
    final area = a.area.isNotEmpty
        ? a.area
        : (a.village.isNotEmpty ? a.village : a.district);
    if (area.isNotEmpty && area != 'Current Location') return area;
    return a.formatted.isNotEmpty ? a.formatted : '';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    final address = ref.watch(defaultAddressProvider);
    final loc = ref.watch(locationControllerProvider);
    // Brand wordmark stays visible at the very top and disappears once the user
    // starts scrolling the feed.
    final showBrand = scrollOffset < 24;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---- VS Mart brand row (collapses on scroll) ----
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.topLeft,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: showBrand ? 1.0 : 0.0,
            child: showBrand
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        Icon(Icons.eco_rounded, size: 20, color: vs.brand),
                        const SizedBox(width: 4),
                        Text('VS Mart',
                            style: AppTypography.headlineSmall.copyWith(
                              color: vs.brand,
                              fontWeight: FontWeight.w800,
                            )),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ),
        // ---- Delivery location + notifications ----
        Row(
          children: [
            Expanded(
              child: _DeliveryLocation(
                state: loc,
                addressLabel: _addressLabel(address),
                onTap: () => context.pushNamed(RouteNames.addresses),
                onEnableLocation: () => ref
                    .read(locationControllerProvider.notifier)
                    .ensureResolved(force: true),
              ),
            ),
            IconButton(
              onPressed: () => context.pushNamed(RouteNames.notifications),
              style: IconButton.styleFrom(
                backgroundColor: context.colors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.brMd,
                  side: BorderSide(color: vs.border),
                ),
              ),
              icon: Icon(Icons.notifications_none_rounded,
                  color: context.colors.onSurface),
            ),
          ],
        ),
      ],
    );
  }
}

/// The "Delivery to <area>" header. Surfaces the live GPS-resolved area, with a
/// shimmer while locating, an "Enable location" CTA on permission denial, and a
/// graceful fall-back to the saved address label.
class _DeliveryLocation extends StatelessWidget {
  const _DeliveryLocation({
    required this.state,
    required this.addressLabel,
    required this.onTap,
    required this.onEnableLocation,
  });

  final DeviceLocationState state;
  final String addressLabel;
  final VoidCallback onTap;
  final VoidCallback onEnableLocation;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;

    // Permission denied → tappable "Enable location".
    if (state.isPermissionDenied && addressLabel.isEmpty) {
      return InkWell(
        onTap: onEnableLocation,
        borderRadius: AppRadius.brSm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Delivery to',
                style:
                    AppTypography.labelSmall.copyWith(color: vs.textSecondary)),
            Row(
              children: [
                Icon(Icons.location_off_rounded, size: 18, color: vs.danger),
                const SizedBox(width: 4),
                Text('Enable location',
                    style: AppTypography.titleMedium.copyWith(color: vs.brand)),
              ],
            ),
          ],
        ),
      );
    }

    // Resolved live location wins; otherwise the saved-address fallback.
    final liveArea = state.location?.displayLabel ?? '';
    final label = liveArea.isNotEmpty
        ? liveArea
        : (addressLabel.isNotEmpty ? addressLabel : 'Set delivery address');

    // Loading with nothing to show yet → subtle shimmer.
    final showShimmer =
        state.isLoading && liveArea.isEmpty && addressLabel.isEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brSm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Delivery to',
              style:
                  AppTypography.labelSmall.copyWith(color: vs.textSecondary)),
          Row(
            children: [
              Icon(Icons.location_on_rounded, size: 18, color: vs.brand),
              const SizedBox(width: 2),
              if (showShimmer)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 3),
                  child: VSShimmerBox(width: 120, height: 14),
                )
              else
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.titleMedium,
                  ),
                ),
              Icon(Icons.keyboard_arrow_down_rounded,
                  size: 20, color: context.colors.onSurface),
            ],
          ),
        ],
      ),
    );
  }
}

/// Auto-scrolling promotional banner carousel sourced from [bannersProvider].
class _OfferCarousel extends ConsumerStatefulWidget {
  const _OfferCarousel({
    this.placement = BannerPlacement.top,
    this.compact = false,
  });

  final BannerPlacement placement;
  final bool compact;

  @override
  ConsumerState<_OfferCarousel> createState() => _OfferCarouselState();
}

class _OfferCarouselState extends ConsumerState<_OfferCarousel> {
  late final PageController _controller =
      PageController(viewportFraction: widget.compact ? 0.86 : 0.92);
  Timer? _timer;
  int _page = 0;

  /// Responsive banner height: a 16:10 hero band, or a shorter 16:9 band for
  /// the [compact] secondary (middle) carousel.
  double _bannerHeight(BuildContext context) {
    final frac = widget.compact ? 0.86 : 0.92;
    final cardWidth = MediaQuery.sizeOf(context).width * frac;
    return widget.compact
        ? (cardWidth * 9 / 16).clamp(140.0, 200.0)
        : (cardWidth * 10 / 16).clamp(200.0, 320.0);
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_controller.hasClients && _controller.position.haveDimensions) {
        _controller.nextPage(
          duration: const Duration(milliseconds: 480),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final banners = ref.watch(bannersProvider);
    final height = _bannerHeight(context);
    return banners.when(
      loading: () => Padding(
        padding: AppSpacing.screenHorizontal,
        child: VSShimmerBox(height: height, borderRadius: AppRadius.brXl),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (all) {
        final offers =
            all.where((o) => o.placement == widget.placement).toList();
        if (offers.isEmpty) return const SizedBox.shrink();
        final count = offers.length;
        final active = _page % count;
        return Column(
          children: [
            SizedBox(
              height: height,
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                // No itemCount → seamless infinite forward loop.
                itemBuilder: (context, i) {
                  final offer = offers[i % count];
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                    child: VSOfferBanner(
                      offer: offer,
                      onTap: () {
                        ref
                            .read(analyticsServiceProvider)
                            .track('offer_clicked', {'offer': offer.id});
                        context.pushNamed(RouteNames.offers);
                      },
                    ),
                  );
                },
              ),
            ),
            AppSpacing.vGapMd,
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < count; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    height: 6,
                    width: i == active ? 20 : 6,
                    decoration: BoxDecoration(
                      color: i == active ? vs.brand : vs.border,
                      borderRadius: AppRadius.brPill,
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// "Special Sale" — a horizontal rail of product-spotlight cards (a product
/// image over a coloured background, Blinkit-style) from spotlight banners.
class _SpotlightSection extends ConsumerWidget {
  const _SpotlightSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spots = (ref.watch(bannersProvider).valueOrNull ?? const <Offer>[])
        .where((o) => o.placement == BannerPlacement.spotlight)
        .toList();
    if (spots.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: AppSpacing.screenHorizontal,
          child: _SectionHeader(title: 'Special Sale 🔥'),
        ),
        AppSpacing.vGapMd,
        SizedBox(
          height: 188,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: AppSpacing.screenHorizontal,
            itemCount: spots.length,
            separatorBuilder: (_, __) => AppSpacing.hGapMd,
            itemBuilder: (context, i) => _SpotlightCard(offer: spots[i]),
          ),
        ),
      ],
    );
  }
}

class _SpotlightCard extends ConsumerWidget {
  const _SpotlightCard({required this.offer});

  final Offer offer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width =
        (MediaQuery.sizeOf(context).width * 0.8).clamp(280.0, 360.0);
    final faint = AppColors.white.withValues(alpha: 0.92);
    final pct = offer.discountPercent ?? 0;
    return GestureDetector(
      onTap: () {
        ref
            .read(analyticsServiceProvider)
            .track('spotlight_clicked', {'offer': offer.id});
        if (offer.productId != null && offer.productId!.isNotEmpty) {
          context.pushNamed(RouteNames.productDetails,
              pathParameters: {'productId': offer.productId!});
        } else {
          context.pushNamed(RouteNames.offers);
        }
      },
      child: Container(
        width: width,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: AppColors.offerGradient,
          borderRadius: AppRadius.brXl,
          boxShadow: AppShadows.glow(AppColors.offerOrange),
        ),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.white.withValues(alpha: 0.22),
                      borderRadius: AppRadius.brSm,
                    ),
                    child: Text(offer.badge ?? 'Special Sale',
                        style: AppTypography.labelSmall
                            .copyWith(color: AppColors.white)),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(offer.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.titleLarge
                              .copyWith(color: AppColors.white)),
                      if (offer.dealPrice != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(offer.dealPrice!.asCurrency,
                                style: AppTypography.priceMedium
                                    .copyWith(color: AppColors.white)),
                            if (offer.originalPrice != null) ...[
                              AppSpacing.hGapSm,
                              Text(offer.originalPrice!.asCurrency,
                                  style: AppTypography.bodySmall.copyWith(
                                    color: faint,
                                    decoration: TextDecoration.lineThrough,
                                  )),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                    decoration: const BoxDecoration(
                      color: AppColors.white,
                      borderRadius: AppRadius.brPill,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Shop Now',
                            style: AppTypography.labelMedium
                                .copyWith(color: AppColors.offerOrange)),
                        const SizedBox(width: 2),
                        const Icon(Icons.arrow_forward_rounded,
                            size: 14, color: AppColors.offerOrange),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            AppSpacing.hGapMd,
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: 104,
                  width: 104,
                  decoration: const BoxDecoration(
                    color: AppColors.white,
                    borderRadius: AppRadius.brLg,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: VSNetworkImage(
                    url: offer.imageUrl,
                    fit: BoxFit.contain,
                    fallbackIcon: Icons.local_offer_rounded,
                  ),
                ),
                if (pct > 0)
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Container(
                      height: 38,
                      width: 38,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.vsGreen,
                        shape: BoxShape.circle,
                      ),
                      child: Text('$pct%\nOFF',
                          textAlign: TextAlign.center,
                          style: AppTypography.labelSmall.copyWith(
                              color: AppColors.white,
                              height: 1.0,
                              fontSize: 9)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final actions = <_QuickAction>[
      _QuickAction(Icons.storefront_rounded, 'Grocery', vs.brand, vs.brandTint,
          () => context.goNamed(RouteNames.categories)),
      _QuickAction(Icons.credit_card_rounded, 'Credit', vs.trust, vs.trustTint,
          () => context.goNamed(RouteNames.creditDashboard)),
      _QuickAction(Icons.receipt_long_rounded, 'Pay Bills', vs.offer,
          vs.offerTint, () => context.goNamed(RouteNames.creditDashboard)),
      _QuickAction(Icons.local_offer_rounded, 'Offers', AppColors.error,
          vs.dangerTint, () => context.pushNamed(RouteNames.offers)),
    ];
    return Row(
      children: [
        for (final a in actions)
          Expanded(
            child: InkWell(
              onTap: a.onTap,
              borderRadius: AppRadius.brLg,
              child: Column(
                children: [
                  Container(
                    height: 52,
                    width: 52,
                    decoration: BoxDecoration(
                        color: a.tint, borderRadius: AppRadius.brLg),
                    child: Icon(a.icon, color: a.color),
                  ),
                  AppSpacing.vGapSm,
                  Text(a.label, style: AppTypography.labelSmall),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _QuickAction {
  const _QuickAction(this.icon, this.label, this.color, this.tint, this.onTap);
  final IconData icon;
  final String label;
  final Color color;
  final Color tint;
  final VoidCallback onTap;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onSeeAll});

  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: AppTypography.titleLarge),
        if (onSeeAll != null)
          GestureDetector(
            onTap: onSeeAll,
            child: Text('See All',
                style: AppTypography.labelMedium
                    .copyWith(color: AppColors.trustBlue)),
          ),
      ],
    );
  }
}

class _CategoryRail extends ConsumerWidget {
  const _CategoryRail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final departments = ref.watch(departmentsProvider);
    return SizedBox(
      height: 104,
      child: departments.when(
        loading: () => const Center(child: VSShimmerBox(height: 80, width: 72)),
        error: (_, __) => const SizedBox.shrink(),
        data: (items) {
          final shown = items.take(6).toList();
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: AppSpacing.screenHorizontal,
            itemCount: shown.length,
            separatorBuilder: (_, __) => AppSpacing.hGapMd,
            itemBuilder: (context, i) {
              final Category c = shown[i];
              return VSCategoryCard(
                icon: categoryIcon(c.iconName),
                label: c.name,
                onTap: () {
                  ref
                      .read(analyticsServiceProvider)
                      .track('category_opened', {'category': c.id});
                  context.pushNamed(
                    RouteNames.subCategories,
                    pathParameters: {'categoryId': c.id},
                    queryParameters: {'title': c.name},
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// Generic horizontal product rail driven by any `List<Product>` provider.
class _ProductRail extends ConsumerWidget {
  const _ProductRail({required this.provider, required this.source});

  final ProviderListenable<AsyncValue<List<Product>>> provider;

  /// Hero-tag source — distinct per rail so the same product across rails never
  /// produces a duplicate Hero tag on Home.
  final String source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);
    return SizedBox(
      height: 268,
      child: async.when(
        loading: () => const Center(child: VSLoadingView()),
        error: (_, __) => const SizedBox.shrink(),
        data: (products) {
          if (products.isEmpty) return const SizedBox.shrink();
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: AppSpacing.screenHorizontal,
            itemCount: products.length,
            separatorBuilder: (_, __) => AppSpacing.hGapMd,
            itemBuilder: (context, i) {
              final p = products[i];
              return SizedBox(
                width: 168,
                child: VSProductCard(
                  name: p.name,
                  unitLabel: p.unit,
                  price: p.price,
                  mrp: p.mrp,
                  rating: p.rating,
                  reviews: p.reviews,
                  imageUrl: p.imageUrl,
                  outOfStock: !p.inStock,
                  heroTag: detailHeroTag(source, p.id),
                  onTap: () => openProductDetail(
                    context,
                    productId: p.id,
                    source: source,
                  ),
                  onAdd: () {
                    ref.read(cartControllerProvider.notifier).addProduct(p);
                    ref.read(analyticsServiceProvider).track(
                        'add_to_cart', {'product': p.id, 'source': 'home'});
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Flash-sale "Today's Deals" section: a header with a live countdown to
/// midnight plus a horizontal rail of deal cards.
class _TodaysDeals extends StatefulWidget {
  const _TodaysDeals();

  @override
  State<_TodaysDeals> createState() => _TodaysDealsState();
}

class _TodaysDealsState extends State<_TodaysDeals> {
  Timer? _timer;
  Duration _left = _untilMidnight();

  static Duration _untilMidnight() {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final diff = end.difference(now);
    return diff.isNegative ? Duration.zero : diff;
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1),
        (_) => setState(() => _left = _untilMidnight()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final h = _two(_left.inHours);
    final m = _two(_left.inMinutes % 60);
    final s = _two(_left.inSeconds % 60);
    return Column(
      children: [
        Padding(
          padding: AppSpacing.screenHorizontal,
          child: Row(
            children: [
              Icon(Icons.bolt_rounded, color: vs.offer, size: 22),
              const SizedBox(width: 4),
              Text("Today's Deals", style: AppTypography.titleLarge),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 3),
                decoration: BoxDecoration(
                  color: vs.offerTint,
                  borderRadius: AppRadius.brSm,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.schedule_rounded, size: 12, color: vs.offer),
                    const SizedBox(width: 4),
                    Text('$h:$m:$s',
                        style: AppTypography.labelSmall.copyWith(
                            color: vs.offer, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => context.pushNamed(RouteNames.todaysDeals),
                child: Text('See All',
                    style: AppTypography.labelMedium
                        .copyWith(color: AppColors.trustBlue)),
              ),
            ],
          ),
        ),
        AppSpacing.vGapMd,
        const _DealsRail(),
      ],
    );
  }
}

/// "Today's Deals" rail sourced from [dealsProvider].
class _DealsRail extends ConsumerWidget {
  const _DealsRail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deals = ref.watch(dealsProvider);
    return SizedBox(
      height: 212,
      child: deals.when(
        loading: () => const Center(child: VSLoadingView()),
        error: (_, __) => const SizedBox.shrink(),
        data: (offers) {
          if (offers.isEmpty) return const SizedBox.shrink();
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: AppSpacing.screenHorizontal,
            itemCount: offers.length,
            separatorBuilder: (_, __) => AppSpacing.hGapMd,
            itemBuilder: (context, i) {
              final o = offers[i];
              return _DealCard(
                offer: o,
                onTap: () {
                  ref
                      .read(analyticsServiceProvider)
                      .track('offer_clicked', {'offer': o.id});
                  if (o.productId != null) {
                    context.pushNamed(RouteNames.productDetails,
                        pathParameters: {'productId': o.productId!});
                  } else {
                    context.pushNamed(RouteNames.offers);
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// Rich "Today's Deal" card: a product image with a discount badge, then the
/// deal title and price below.
class _DealCard extends StatelessWidget {
  const _DealCard({required this.offer, required this.onTap});

  final Offer offer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final hasDiscount =
        offer.discountPercent != null && offer.discountPercent! > 0;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brLg,
      child: Container(
        width: 160,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: AppRadius.brLg,
          border: Border.all(color: vs.border),
          boxShadow: AppShadows.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---- Image (fills available height) with discount badge ----
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      color: vs.brandTint.withValues(alpha: 0.4),
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: VSNetworkImage(
                        url: offer.imageUrl,
                        fit: BoxFit.contain,
                        borderRadius: AppRadius.brSm,
                        fallbackIcon: Icons.local_offer_rounded,
                      ),
                    ),
                  ),
                  if (hasDiscount)
                    Positioned(
                      top: AppSpacing.xs,
                      left: AppSpacing.xs,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm, vertical: 2),
                        decoration: BoxDecoration(
                            color: vs.offer, borderRadius: AppRadius.brSm),
                        child: Text('${offer.discountPercent}% OFF',
                            style: AppTypography.labelSmall
                                .copyWith(color: AppColors.white)),
                      ),
                    ),
                ],
              ),
            ),
            // ---- Info ----
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(offer.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.titleMedium),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (offer.dealPrice != null)
                        Text(offer.dealPrice!.asCurrency,
                            style: AppTypography.priceMedium),
                      if (offer.originalPrice != null) ...[
                        AppSpacing.hGapSm,
                        Flexible(
                          child: Text(offer.originalPrice!.asCurrency,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodySmall.copyWith(
                                color: vs.textSecondary,
                                decoration: TextDecoration.lineThrough,
                              )),
                        ),
                      ],
                    ],
                  ),
                  if (offer.savings > 0) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: 1),
                      decoration: BoxDecoration(
                        color: vs.success.withValues(alpha: 0.14),
                        borderRadius: AppRadius.brXs,
                      ),
                      child: Text('Save ${offer.savings.asCurrency}',
                          style: AppTypography.labelSmall.copyWith(
                              color: vs.success, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
