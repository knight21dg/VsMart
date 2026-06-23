import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/offer.dart';
import '../providers/offer_providers.dart';

/// Opens the product behind a deal (or the Offers hub when it has no product).
void _openDeal(BuildContext context, Offer offer) {
  if (offer.productId != null) {
    context.pushNamed(
      RouteNames.productDetails,
      pathParameters: {'productId': offer.productId!},
    );
  } else {
    context.pushNamed(RouteNames.offers);
  }
}

/// Today's Deals — matches the design: a "FLASH SALE" gradient header with a
/// live countdown, quick filter chips, a highlighted "Selling Fast" deal, and a
/// 2-column "Top Deals" grid. Tapping any deal shows a snack (no navigation).
class TodaysDealsScreen extends ConsumerWidget {
  const TodaysDealsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deals = ref.watch(dealsProvider);

    return Scaffold(
      appBar: const VSAppBar(title: "Today's Deals"),
      body: SafeArea(
        top: false,
        child: deals.when(
          loading: () => const VSLoadingView(message: 'Loading deals…'),
          error: (_, __) => VSErrorView(
            onRetry: () => ref.invalidate(dealsProvider),
          ),
          data: (items) {
            if (items.isEmpty) {
              return const VSEmptyState(
                icon: Icons.local_fire_department_rounded,
                title: 'No deals right now',
                message: 'Check back soon for fresh savings.',
              );
            }

            final featured = items.first;
            final grid = items.length > 1 ? items.sublist(1) : const <Offer>[];

            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(dealsProvider),
              child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xxl,
              ),
              children: [
                const _FlashHeader(),
                AppSpacing.vGapLg,
                const _FilterChips(),
                AppSpacing.vGapLg,
                _SectionHeader(
                  icon: Icons.bolt_rounded,
                  iconColor: context.vsColors.offer,
                  label: 'Selling Fast',
                ),
                AppSpacing.vGapSm,
                _SellingFastCard(
                  offer: featured,
                  onTap: () => _openDeal(context, featured),
                ),
                if (grid.isNotEmpty) ...[
                  AppSpacing.vGapLg,
                  _SectionHeader(
                    icon: Icons.local_offer_rounded,
                    iconColor: context.vsColors.brand,
                    label: 'Top Deals',
                    trailing: TextButton(
                      onPressed: () => context.pushNamed(RouteNames.offers),
                      child: Text(
                        'View All',
                        style: AppTypography.labelLarge
                            .copyWith(color: AppColors.vsGreen),
                      ),
                    ),
                  ),
                  AppSpacing.vGapSm,
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: grid.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: AppSpacing.md,
                      crossAxisSpacing: AppSpacing.md,
                      childAspectRatio: 0.64,
                    ),
                    itemBuilder: (context, i) => _DealCard(
                      offer: grid[i],
                      onTap: () => _openDeal(context, grid[i]),
                    ),
                  ),
                ],
              ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Orange gradient flash-sale banner with a live HH:MM:SS countdown.
class _FlashHeader extends StatefulWidget {
  const _FlashHeader();

  @override
  State<_FlashHeader> createState() => _FlashHeaderState();
}

class _FlashHeaderState extends State<_FlashHeader> {
  Duration _left = const Duration(hours: 4, minutes: 45, seconds: 12);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _left = _left.inSeconds <= 0
            ? Duration.zero
            : _left - const Duration(seconds: 1);
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final faint = AppColors.white.withValues(alpha: 0.9);
    final h = _two(_left.inHours);
    final m = _two(_left.inMinutes.remainder(60));
    final s = _two(_left.inSeconds.remainder(60));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: const BoxDecoration(
        gradient: AppColors.offerGradient,
        borderRadius: AppRadius.brXl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.22),
              borderRadius: AppRadius.brPill,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.flash_on_rounded,
                    size: 14, color: AppColors.white),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'FLASH SALE',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.white,
                  ),
                ),
              ],
            ),
          ),
          AppSpacing.vGapMd,
          Text(
            "Today's Mega Savings",
            style:
                AppTypography.displayMedium.copyWith(color: AppColors.white),
          ),
          AppSpacing.vGapXs,
          Text(
            'Up to 60% off on fresh produce & essentials',
            style: AppTypography.bodyMedium.copyWith(color: faint),
          ),
          AppSpacing.vGapLg,
          Row(
            children: [
              const Icon(Icons.timer_outlined,
                  size: 18, color: AppColors.white),
              AppSpacing.hGapSm,
              _CountBox(value: h),
              const _CountSeparator(),
              _CountBox(value: m),
              const _CountSeparator(),
              _CountBox(value: s),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountBox extends StatelessWidget {
  const _CountBox({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.textPrimary.withValues(alpha: 0.35),
        borderRadius: AppRadius.brSm,
      ),
      child: Text(
        value,
        style: AppTypography.titleMedium.copyWith(color: AppColors.white),
      ),
    );
  }
}

class _CountSeparator extends StatelessWidget {
  const _CountSeparator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Text(
        ':',
        style: AppTypography.titleMedium.copyWith(color: AppColors.white),
      ),
    );
  }
}

/// Static quick-filter chips (illustrative — match the design row).
class _FilterChips extends StatelessWidget {
  const _FilterChips();

  static const _labels = ['Flash Sale', 'Top Discounts', 'Buy 1 Get 1'];

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _labels.length,
        separatorBuilder: (_, __) => AppSpacing.hGapSm,
        itemBuilder: (context, i) {
          final selected = i == 0;
          return Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            decoration: BoxDecoration(
              color: selected ? AppColors.vsGreen : context.colors.surface,
              borderRadius: AppRadius.brPill,
              border: Border.all(color: selected ? AppColors.vsGreen : vs.border),
            ),
            child: Text(
              _labels[i],
              style: AppTypography.labelMedium.copyWith(
                color: selected ? AppColors.white : vs.textSecondary,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.trailing,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: iconColor),
        AppSpacing.hGapSm,
        Text(label, style: AppTypography.titleLarge),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Highlighted horizontal "Selling Fast" deal with a stock-claimed progress bar.
class _SellingFastCard extends StatelessWidget {
  const _SellingFastCard({required this.offer, required this.onTap});

  final Offer offer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brLg,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: AppRadius.brLg,
          border: Border.all(color: vs.border),
          boxShadow: AppShadows.xs,
        ),
        child: Row(
          children: [
            _Thumb(offer: offer, size: 88, accent: vs.offer),
            AppSpacing.hGapMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (offer.discountPercent != null && offer.discountPercent! > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: VSStatusChip(
                        label: '${offer.discountPercent}% OFF',
                        tone: VSStatusTone.offer,
                        dense: true,
                      ),
                    ),
                  Text(
                    offer.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.titleMedium,
                  ),
                  AppSpacing.vGapXs,
                  _PriceRow(offer: offer),
                  AppSpacing.vGapSm,
                  Row(
                    children: [
                      Icon(Icons.local_fire_department_rounded,
                          size: 14, color: vs.offer),
                      const SizedBox(width: 4),
                      Text(
                        'Only 5 left!',
                        style: AppTypography.labelSmall.copyWith(color: vs.offer),
                      ),
                      const Spacer(),
                      Text(
                        '80% Claimed',
                        style: AppTypography.labelSmall
                            .copyWith(color: vs.textSecondary),
                      ),
                    ],
                  ),
                  AppSpacing.vGapXs,
                  ClipRRect(
                    borderRadius: AppRadius.brPill,
                    child: LinearProgressIndicator(
                      value: 0.8,
                      minHeight: 5,
                      backgroundColor: vs.border,
                      valueColor: AlwaysStoppedAnimation<Color>(vs.offer),
                    ),
                  ),
                ],
              ),
            ),
            AppSpacing.hGapMd,
            _AddButton(onTap: onTap),
          ],
        ),
      ),
    );
  }
}

/// Compact 2-column grid deal card with a discount badge and add button.
class _DealCard extends StatelessWidget {
  const _DealCard({required this.offer, required this.onTap});

  final Offer offer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final discount = offer.discountPercent;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brLg,
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: AppRadius.brLg,
          border: Border.all(color: vs.border),
          boxShadow: AppShadows.xs,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                _Thumb(offer: offer, size: double.infinity, height: 120),
                if (discount != null && discount > 0)
                  Positioned(
                    top: AppSpacing.sm,
                    left: AppSpacing.sm,
                    child: VSStatusChip(
                      label: '$discount% OFF',
                      tone: VSStatusTone.offer,
                      dense: true,
                    ),
                  ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      offer.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.titleMedium,
                    ),
                    if (offer.subtitle.isNotEmpty) ...[
                      AppSpacing.vGapXs,
                      Text(
                        offer.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelSmall
                            .copyWith(color: vs.textSecondary),
                      ),
                    ],
                    const Spacer(),
                    _PriceRow(offer: offer),
                    AppSpacing.vGapXs,
                    Row(
                      children: [
                        if (offer.savings > 0)
                          Expanded(
                            child: VSStatusChip(
                              label: 'Save ${offer.savings.asCurrency}',
                              tone: VSStatusTone.success,
                              dense: true,
                            ),
                          )
                        else
                          const Spacer(),
                        _AddButton(onTap: onTap),
                      ],
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

/// Deal price + struck-through original price.
class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.offer});

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
          Flexible(
            child: Text(
              price.asCurrency,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.priceMedium.copyWith(color: vs.brand),
            ),
          ),
        if (original != null && original > (price ?? 0)) ...[
          AppSpacing.hGapSm,
          Flexible(
            child: Text(
              original.asCurrency,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall.copyWith(
                color: vs.textSecondary,
                decoration: TextDecoration.lineThrough,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Square product thumbnail; falls back to a tinted icon when there's no image.
class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.offer,
    required this.size,
    this.height,
    this.accent,
  });

  final Offer offer;
  final double size;
  final double? height;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final tint = accent ?? vs.brand;
    final image = offer.imageUrl;

    if (image == null || image.isEmpty) {
      return ClipRRect(
        borderRadius: AppRadius.brMd,
        child: Container(
          width: size,
          height: height ?? size,
          color: tint.withValues(alpha: 0.12),
          alignment: Alignment.center,
          child: Icon(Icons.shopping_basket_rounded, color: tint, size: 36),
        ),
      );
    }

    return VSNetworkImage(
      url: image,
      width: size,
      height: height ?? size,
      fit: BoxFit.cover,
    );
  }
}

/// Circular green "+" add-to-cart affordance.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          color: AppColors.vsGreen,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.add_rounded, color: AppColors.white, size: 20),
      ),
    );
  }
}
