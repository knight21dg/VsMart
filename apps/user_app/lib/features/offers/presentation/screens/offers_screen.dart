import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../checkout/presentation/providers/checkout_controller.dart';
import '../../domain/entities/offer.dart';
import '../providers/offer_providers.dart';

/// Offers & Deals — matches the design: promo hero, active coupons, special
/// deals (BOGO / combo / flash), VS Credit cashback, and an expiring-soon
/// countdown, with a sticky "Start Shopping" CTA.
class OffersScreen extends ConsumerWidget {
  const OffersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coupons = ref.watch(couponsProvider);
    final deals = ref.watch(dealsProvider);

    Future<void> refresh() async {
      ref
        ..invalidate(couponsProvider)
        ..invalidate(dealsProvider);
      await ref.read(couponsProvider.future);
    }

    return Scaffold(
      appBar: VSAppBar(
        title: context.l10n.offersAndDeals,
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () => context.pushNamed(RouteNames.search),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xxl),
            children: [
              const _HeroBanner(),
              AppSpacing.vGapLg,
              _SectionTitle(
                  icon: Icons.confirmation_number_rounded,
                  label: context.l10n.offersActiveCoupons,
                  color: AppColors.vsGreen),
              AppSpacing.vGapSm,
              coupons.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: VSShimmerBox(height: 80, borderRadius: AppRadius.brLg),
                ),
                error: (_, __) => _ErrorRow(
                    onRetry: () => ref.invalidate(couponsProvider)),
                data: (items) => items.isEmpty
                    ? _EmptyRow(message: context.l10n.offersNoCoupons)
                    : Column(
                        children: [
                          for (final c in items)
                            Padding(
                              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                              child: _CouponRow(offer: c),
                            ),
                        ],
                      ),
              ),
              AppSpacing.vGapMd,
              _SectionTitle(
                  icon: Icons.local_fire_department_rounded,
                  label: context.l10n.offersSpecialDeals,
                  color: AppColors.offerOrange),
              AppSpacing.vGapSm,
              // Real deals from the backend (`dealsProvider`). Each card shows
              // only fields the deal actually carries — no invented BOGO/
              // cashback/countdown promos.
              deals.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: VSShimmerBox(height: 96, borderRadius: AppRadius.brLg),
                ),
                error: (_, __) => _ErrorRow(
                    message: context.l10n.offersCouldntLoadDeals,
                    onRetry: () => ref.invalidate(dealsProvider)),
                data: (items) => items.isEmpty
                    ? _EmptyRow(message: context.l10n.offersNoDeals)
                    : Column(
                        children: [
                          for (final d in items)
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: AppSpacing.sm),
                              child: _DealRow(
                                offer: d,
                                onTap: () => _openDeal(context, d),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: AppSpacing.screen,
          child: VSButton(
            label: context.l10n.commonStartShopping,
            icon: Icons.shopping_bag_outlined,
            onPressed: () => context.pushNamed(RouteNames.products),
          ),
        ),
      ),
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner();

  @override
  Widget build(BuildContext context) {
    final faint = AppColors.white.withValues(alpha: 0.9);
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
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.22),
              borderRadius: AppRadius.brSm,
            ),
            child: Text(context.l10n.offersLimitedTime,
                style:
                    AppTypography.labelSmall.copyWith(color: AppColors.white)),
          ),
          AppSpacing.vGapSm,
          Text(context.l10n.offersUpTo60Off,
              style:
                  AppTypography.displayMedium.copyWith(color: AppColors.white)),
          Text(context.l10n.offersOnGroceries,
              style: AppTypography.bodyMedium.copyWith(color: faint)),
          AppSpacing.vGapMd,
          FilledButton(
            onPressed: () => context.pushNamed(RouteNames.todaysDeals),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.white,
              foregroundColor: AppColors.vsGreen,
              elevation: 0,
              shape:
                  const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
            ),
            child: Text(context.l10n.homeShopNow,
                style: AppTypography.labelLarge
                    .copyWith(color: AppColors.vsGreen)),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(
      {required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        AppSpacing.hGapSm,
        Text(label, style: AppTypography.titleLarge),
      ],
    );
  }
}

class _CouponRow extends ConsumerWidget {
  const _CouponRow({required this.offer});

  final Offer offer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    final code = offer.code ?? 'OFFER';
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: vs.brandTint,
              borderRadius: AppRadius.brMd,
            ),
            child: Icon(Icons.local_offer_rounded, color: vs.brand),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(code, style: AppTypography.titleMedium),
                Text(
                  offer.subtitle.isNotEmpty ? offer.subtitle : offer.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall
                      .copyWith(color: vs.textSecondary),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              // Carry the coupon into checkout: it auto-applies (with server
              // validation) once the shopper reaches the checkout screen, so
              // they never have to re-type it. Land them on the cart to continue.
              ref.read(pendingCouponProvider.notifier).state = code;
              context.showSnack('$code will be applied at checkout');
              context.goNamed(RouteNames.cart);
            },
            child: Text(context.l10n.commonApply,
                style: AppTypography.labelLarge
                    .copyWith(color: AppColors.trustBlue)),
          ),
        ],
      ),
    );
  }
}

/// Opens the product behind a deal, or the full Today's Deals hub when the deal
/// has no linked product. Mirrors the Today's Deals screen's tap behaviour.
void _openDeal(BuildContext context, Offer offer) {
  if (offer.productId != null && offer.productId!.isNotEmpty) {
    context.pushNamed(
      RouteNames.productDetails,
      pathParameters: {'productId': offer.productId!},
    );
  } else {
    context.pushNamed(RouteNames.todaysDeals);
  }
}

/// A single backend deal: thumbnail, real title/subtitle, real deal/original
/// price and (when present) the real discount percentage. Renders only what the
/// [Offer] actually carries.
class _DealRow extends StatelessWidget {
  const _DealRow({required this.offer, required this.onTap});

  final Offer offer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final image = offer.imageUrl;
    final discount = offer.discountPercent;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brLg,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: AppRadius.brLg,
          border: Border.all(color: vs.border),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: AppRadius.brMd,
              child: (image == null || image.isEmpty)
                  ? Container(
                      width: 56,
                      height: 56,
                      color: vs.offerTint,
                      alignment: Alignment.center,
                      child:
                          Icon(Icons.local_offer_rounded, color: vs.offer),
                    )
                  : VSNetworkImage(
                      url: image, width: 56, height: 56, fit: BoxFit.cover),
            ),
            AppSpacing.hGapMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(offer.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.titleMedium),
                  if (offer.subtitle.isNotEmpty)
                    Text(offer.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall
                            .copyWith(color: vs.textSecondary)),
                  if (offer.dealPrice != null) ...[
                    AppSpacing.vGapXs,
                    _DealPriceRow(offer: offer),
                  ],
                ],
              ),
            ),
            if (discount != null && discount > 0) ...[
              AppSpacing.hGapSm,
              VSStatusChip(
                label: context.l10n.discountPercentOff(discount),
                tone: VSStatusTone.offer,
                dense: true,
              ),
            ] else
              Icon(Icons.chevron_right_rounded, color: vs.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// Real deal price with the struck-through original when the backend supplies
/// both.
class _DealPriceRow extends StatelessWidget {
  const _DealPriceRow({required this.offer});

  final Offer offer;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final price = offer.dealPrice;
    final original = offer.originalPrice;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (price != null)
          Text(price.asCurrency,
              style: AppTypography.priceMedium.copyWith(color: vs.brand)),
        if (original != null && original > (price ?? 0)) ...[
          AppSpacing.hGapSm,
          Text(
            original.asCurrency,
            style: AppTypography.bodySmall.copyWith(
              color: vs.textSecondary,
              decoration: TextDecoration.lineThrough,
            ),
          ),
        ],
      ],
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Text(message,
          style: AppTypography.bodyMedium
              .copyWith(color: context.vsColors.textSecondary)),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.onRetry, this.message});

  final VoidCallback onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(message ?? context.l10n.offersCouldntLoadCoupons,
              style: AppTypography.bodyMedium),
        ),
        TextButton(onPressed: onRetry, child: Text(context.l10n.commonRetry)),
      ],
    );
  }
}
