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
import '../../../collections/presentation/pending_collection_banner.dart';
import '../../../address/domain/entities/address.dart';
import '../../../address/presentation/providers/address_providers.dart';
import '../../../address/presentation/providers/address_selection_provider.dart';
import '../../../catalog/domain/entities/category.dart';
import '../../../catalog/domain/entities/product.dart';
import '../../../catalog/presentation/category_icons.dart';
import '../../../catalog/presentation/product_navigation.dart';
import '../../../catalog/presentation/product_share.dart';
import '../../../catalog/presentation/providers/catalog_providers.dart';
import '../../../catalog/presentation/providers/recently_viewed_provider.dart';
import '../../../credit/presentation/providers/credit_providers.dart';
import '../../../location/presentation/providers/location_providers.dart';
import '../../../offers/domain/entities/banner_spec.dart';
import '../../../offers/domain/entities/offer.dart';
import '../../../offers/presentation/offer_link.dart';
import '../../../offers/presentation/providers/banner_event_sink.dart';
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
      ..invalidate(featuredProductsProvider)
      ..invalidate(departmentsProvider)
      ..invalidate(popularProductsProvider)
      ..invalidate(recommendedProductsProvider)
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
                          // An agent may be at the door right now — this needs
                          // to be the first thing seen, not buried in Credit.
                          const PendingCollectionBanner(),
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
                              title: context.l10n.homeExploreCategories,
                              onSeeAll: () =>
                                  context.goNamed(RouteNames.categories),
                            ),
                          ),
                          AppSpacing.vGapMd,
                          const _CategoryRail(),
                          AppSpacing.vGapXl,
                          const _OfferCarousel(
                            placement: BannerPlacement.middle,
                          ),
                          AppSpacing.vGapXl,
                          Padding(
                            padding: AppSpacing.screenHorizontal,
                            child: _SectionHeader(
                              title: context.l10n.homePopularProducts,
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
                              title: context.l10n.homeRecommended,
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
                                title: context.l10n.homeRecentlyOrdered,
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
                            Padding(
                              padding: AppSpacing.screenHorizontal,
                              child: _SectionHeader(
                                  title: context.l10n.homeContinueShopping),
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
                    Text(context.l10n.homeOrderNumber(order.id),
                        style: AppTypography.titleMedium),
                    Text(context.l10n.homeTapToTrack,
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
        hint: context.l10n.homeSearchHint,
        onTap: onTap,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SearchHeaderDelegate oldDelegate) => false;
}

/// What the "Deliver to" header shows.
///
/// The **chosen delivery address wins**; live GPS is only a fallback. This used
/// to be reversed, so standing in one town while delivering to another showed
/// the town you were standing in — the header contradicted where the order was
/// actually going. An explicit choice must always beat an inferred one; live
/// location is just a helpful default for a customer who hasn't picked yet.
String resolveDeliveryLabel({
  required String addressLabel,
  required String liveArea,
  String empty = 'Set delivery address',
}) {
  if (addressLabel.isNotEmpty) return addressLabel;
  if (liveArea.isNotEmpty) return liveArea;
  return empty;
}

class _HomeHeader extends ConsumerWidget {
  const _HomeHeader({required this.scrollOffset});

  final double scrollOffset;

  /// Label for the address the order will actually go to.
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
    // The address the customer actually chose to deliver to — the same source
    // checkout, cart, catalog and serviceability read. This used to watch
    // `defaultAddressProvider`, so picking a different delivery address left
    // the header advertising the wrong place.
    final address = ref.watch(selectedAddressProvider);
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
            Text(context.l10n.homeDeliverTo,
                style:
                    AppTypography.labelSmall.copyWith(color: vs.textSecondary)),
            Row(
              children: [
                Icon(Icons.location_off_rounded, size: 18, color: vs.danger),
                const SizedBox(width: 4),
                Text(context.l10n.homeEnableLocation,
                    style: AppTypography.titleMedium.copyWith(color: vs.brand)),
              ],
            ),
          ],
        ),
      );
    }

    final liveArea = state.location?.displayLabel ?? '';
    final label = resolveDeliveryLabel(
      addressLabel: addressLabel,
      liveArea: liveArea,
    );

    // Loading with nothing to show yet → subtle shimmer.
    final showShimmer =
        state.isLoading && liveArea.isEmpty && addressLabel.isEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brSm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.homeDeliverTo,
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
  const _OfferCarousel({this.placement = BannerPlacement.top});

  /// Drives both the data filter and the slot geometry (via [BannerSpec]).
  final BannerPlacement placement;

  @override
  ConsumerState<_OfferCarousel> createState() => _OfferCarouselState();
}

class _OfferCarouselState extends ConsumerState<_OfferCarousel> {
  /// Geometry contract for this slot — mirrors the server's crop ratio, so the
  /// stored artwork fills the box without `BoxFit.cover` re-cropping it.
  BannerSpec get _spec => BannerSpec.forPlacement(widget.placement.wire);

  /// Horizontal padding inside each page (both sides), excluded from the card
  /// width so the rendered box is the true image ratio.
  static const _pageInset = AppSpacing.xs * 2;

  late final PageController _controller =
      PageController(viewportFraction: _spec.viewportFraction);
  Timer? _timer;
  int _page = 0;

  double _bannerHeight(BuildContext context) => _spec.heightFor(
        MediaQuery.sizeOf(context).width,
        horizontalInset: _pageInset,
      );

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
      // Inset by the same amount as a carousel page so the skeleton occupies the
      // exact box the banner will — no width jump on first paint.
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: VSShimmerBox(height: height, borderRadius: AppRadius.brXl),
      ),
      // The primary (top) hero surfaces a retry; the secondary compact carousel
      // stays quiet on failure since retrying re-fetches the shared provider.
      error: (_, __) => widget.placement == BannerPlacement.top
          ? _RailError(
              height: height,
              onRetry: () => ref.invalidate(bannersProvider),
            )
          : const SizedBox.shrink(),
      data: (all) {
        final offers =
            all.where((o) => o.placement == widget.placement).toList();
        if (offers.isEmpty) return const SizedBox.shrink();
        final count = offers.length;
        final active = _page % count;
        // Fire an impression for the visible banner (deduped by the sink).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(bannerEventSinkProvider).impression(offers[active].id);
          }
        });
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
                      onTap: () => handleOfferTap(context, ref, offer,
                          placement: widget.placement.name),
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
    final bannersAsync = ref.watch(bannersProvider);
    final spots = (bannersAsync.valueOrNull ?? const <Offer>[])
        .where((o) => o.placement == BannerPlacement.spotlight)
        .toList();
    if (spots.isEmpty) {
      // Banners failed with nothing cached → show a compact retry instead of
      // vanishing (which reads as an empty catalog).
      if (bannersAsync.hasError && !bannersAsync.hasValue) {
        return _RailError(
          height: 96,
          onRetry: () => ref.invalidate(bannersProvider),
        );
      }
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: AppSpacing.screenHorizontal,
          child: _SectionHeader(title: context.l10n.homeSpecialSale),
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
      // Route through the shared handler so spotlight cards honour the banner's
      // configured action/payload (and emit click events) like every other
      // placement — they used to hardcode "open the product, else the hub",
      // silently ignoring whatever the admin set.
      onTap: () => handleOfferTap(context, ref, offer, placement: 'spotlight'),
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
                        Text(context.l10n.homeShopNow,
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
            child: Text(context.l10n.commonSeeAll,
                style: AppTypography.labelMedium
                    .copyWith(color: AppColors.trustBlue)),
          ),
      ],
    );
  }
}

/// Compact, retryable failure state for a home sub-rail. A failed rail that
/// silently collapses can read as an empty catalog, so we keep the section
/// visible with a subtle inline "Couldn't load — Retry" row sized to the rail.
class _RailError extends StatelessWidget {
  const _RailError({required this.onRetry, this.height});

  final VoidCallback onRetry;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 16, color: vs.textSecondary),
            AppSpacing.hGapSm,
            Text(context.l10n.homeCouldntLoad,
                style: AppTypography.bodySmall
                    .copyWith(color: vs.textSecondary)),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: vs.brand,
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              child: Text(context.l10n.commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryRail extends ConsumerWidget {
  const _CategoryRail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The serving store's OWN category tree (location-scoped), not the global
    // `/categories` catalog — which is empty in production, so the home rail was
    // always blank. Tapping opens the Categories tab to drill in.
    final categories = ref.watch(storeCategoriesProvider(null));
    return SizedBox(
      height: 104,
      child: categories.when(
        loading: () => const Center(child: VSShimmerBox(height: 80, width: 72)),
        error: (_, __) => _RailError(
            onRetry: () => ref.invalidate(storeCategoriesProvider(null))),
        data: (items) {
          if (items.isEmpty) return const SizedBox.shrink();
          final shown = items.take(6).toList();
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: AppSpacing.screenHorizontal,
            itemCount: shown.length,
            separatorBuilder: (_, __) => AppSpacing.hGapMd,
            itemBuilder: (context, i) {
              final Category c = shown[i];
              return VSCategoryCard(
                // The admin-set category image; the icon is only the fallback.
                // Omitting this left every home category as the same generic
                // tinted icon even when artwork existed.
                imageUrl: c.imageUrl,
                icon: categoryIcon(c.iconName),
                label: c.name,
                onTap: () {
                  ref
                      .read(analyticsServiceProvider)
                      .track('category_opened', {'category': c.id});
                  context.goNamed(RouteNames.categories);
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

  final FutureProvider<List<Product>> provider;

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
        error: (_, __) => _RailError(onRetry: () => ref.invalidate(provider)),
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
                  price: p.displayPrice,
                  mrp: p.displayMrp,
                  imageUrl: p.imageUrl,
                  outOfStock: !p.effectiveInStock,
                  heroTag: detailHeroTag(source, p.id),
                  onShareTap: () => shareProductLink(context, ref, p),
                  onTap: () => openProductDetail(
                    context,
                    productId: p.id,
                    source: source,
                  ),
                  onAdd: () {
                    addToCartOrChoose(context, ref, p, source: source);
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
              Text(context.l10n.offersTodaysDeals,
                  style: AppTypography.titleLarge),
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
                child: Text(context.l10n.commonSeeAll,
                    style: AppTypography.labelMedium
                        .copyWith(color: AppColors.trustBlue)),
              ),
            ],
          ),
        ),
        AppSpacing.vGapMd,
        // Was _DealsRail() — bound to dealsProvider (/offers?type=deal, the
        // marketing-banner Offer model), a completely different feature from
        // the one this section is meant to show: the curated/algorithmic
        // "Today's Deals" rail (HomeFeature.TODAY_DEALS, GET
        // /home/sections/today_deals, admin-curatable from Marketing > Home
        // Screen). Nobody creating an Offer(type=deal) meant admin curation
        // here had zero effect, and the rail read as permanently empty
        // (silent SizedBox.shrink()) since a fresh install has no such Offer
        // rows. _ProductRail is the same widget Popular/Recommended already
        // use against this exact home/sections family.
        _ProductRail(provider: featuredProductsProvider, source: 'home-deals'),
      ],
    );
  }
}

// _DealsRail / _DealCard removed — replaced by _ProductRail(featuredProductsProvider)
// above, which is bound to the actual "Today's Deals" backend feature. See the
// comment at the _ProductRail(provider: featuredProductsProvider, ...) call site.
