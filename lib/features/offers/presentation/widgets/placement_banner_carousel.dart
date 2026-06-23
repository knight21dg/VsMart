import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../domain/entities/offer.dart';
import '../providers/offer_providers.dart';
import 'vs_offer_banner.dart';

/// Dynamic, category-targeted promotional banner carousel for the product-list
/// and product-detail screens. Mirrors the home banner look ([VSOfferBanner])
/// and behaviour, but sources banners from [placementBannersProvider] using the
/// screen [placement] plus optional category / sub-category targeting.
///
/// Renders nothing when there are no banners (loading, error, or empty) so it
/// never leaves an empty gap. Set [single] to show just one banner (no
/// auto-scrolling / dots) — used on the product-detail screen.
class PlacementBannerCarousel extends ConsumerStatefulWidget {
  const PlacementBannerCarousel({
    super.key,
    required this.placement,
    this.categoryId,
    this.subcategoryId,
    this.single = false,
    this.padding = AppSpacing.screenHorizontal,
    this.trailingGap = 0,
  });

  /// Server placement string, e.g. `product_list` or `product_detail`.
  final String placement;
  final String? categoryId;
  final String? subcategoryId;

  /// When true, show a single banner with no carousel chrome.
  final bool single;

  final EdgeInsetsGeometry padding;

  /// Space added below the carousel — only when it actually renders banners,
  /// so an empty placement leaves no gap.
  final double trailingGap;

  @override
  ConsumerState<PlacementBannerCarousel> createState() =>
      _PlacementBannerCarouselState();
}

class _PlacementBannerCarouselState
    extends ConsumerState<PlacementBannerCarousel> {
  final _controller = PageController(viewportFraction: 0.92);
  Timer? _timer;
  int _page = 0;

  double _bannerHeight(BuildContext context) {
    final cardWidth = MediaQuery.sizeOf(context).width * 0.92;
    return (cardWidth * 9 / 16).clamp(140.0, 220.0);
  }

  @override
  void initState() {
    super.initState();
    if (!widget.single) {
      _timer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (_controller.hasClients && _controller.position.haveDimensions) {
          _controller.nextPage(
            duration: const Duration(milliseconds: 480),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onTap(Offer offer) {
    ref.read(analyticsServiceProvider).track('banner_clicked', {
      'offer': offer.id,
      'placement': widget.placement,
    });
    // Mirror home behaviour: jump to a linked product if present, else open
    // the offers hub.
    final productId = offer.productId;
    if (productId != null && productId.isNotEmpty) {
      context.pushNamed(
        RouteNames.productDetails,
        pathParameters: {'productId': productId},
      );
    } else {
      context.pushNamed(RouteNames.offers);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final banners = ref.watch(placementBannersProvider((
      placement: widget.placement,
      categoryId: widget.categoryId,
      subcategoryId: widget.subcategoryId,
    )));

    final offers = banners.valueOrNull ?? const <Offer>[];
    // Render nothing for loading / error / empty — no placeholder box.
    if (offers.isEmpty) return const SizedBox.shrink();

    final height = _bannerHeight(context);

    if (widget.single) {
      return Padding(
        padding: widget.padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: height,
              child: VSOfferBanner(
                offer: offers.first,
                onTap: () => _onTap(offers.first),
              ),
            ),
            if (widget.trailingGap > 0) SizedBox(height: widget.trailingGap),
          ],
        ),
      );
    }

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
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: VSOfferBanner(
                  offer: offer,
                  onTap: () => _onTap(offer),
                ),
              );
            },
          ),
        ),
        if (count > 1) ...[
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
        if (widget.trailingGap > 0) SizedBox(height: widget.trailingGap),
      ],
    );
  }
}
