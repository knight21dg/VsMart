import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
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

    Future<void> refresh() async {
      ref
        ..invalidate(couponsProvider)
        ..invalidate(dealsProvider);
      await ref.read(couponsProvider.future);
    }

    return Scaffold(
      appBar: VSAppBar(
        title: 'Offers & Deals',
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
              const _SectionTitle(
                  icon: Icons.confirmation_number_rounded,
                  label: 'Active Coupons',
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
                    ? const _EmptyRow(message: 'No coupons available.')
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
              const _SectionTitle(
                  icon: Icons.star_rounded,
                  label: 'Special Deals',
                  color: AppColors.offerOrange),
              AppSpacing.vGapSm,
              _BogoCard(onTap: () => context.pushNamed(RouteNames.products)),
              AppSpacing.vGapMd,
              Row(
                children: [
                  Expanded(
                    child: _MiniDealCard(
                      icon: Icons.widgets_rounded,
                      title: 'Combo Offers',
                      subtitle: 'Save up to 35%',
                      color: AppColors.trustBlue,
                      onTap: () => context.pushNamed(RouteNames.products),
                    ),
                  ),
                  AppSpacing.hGapMd,
                  Expanded(
                    child: _MiniDealCard(
                      icon: Icons.flash_on_rounded,
                      title: 'Flash Deals',
                      subtitle: 'Limited time',
                      color: AppColors.offerOrange,
                      onTap: () => context.pushNamed(RouteNames.products),
                    ),
                  ),
                ],
              ),
              AppSpacing.vGapMd,
              const _SectionTitle(
                  icon: Icons.account_balance_wallet_rounded,
                  label: 'Cashback Offers',
                  color: AppColors.trustBlue),
              AppSpacing.vGapSm,
              _CashbackCard(
                  onTap: () => context.goNamed(RouteNames.creditDashboard)),
              AppSpacing.vGapMd,
              const _SectionTitle(
                  icon: Icons.timer_outlined,
                  label: 'Expiring Soon',
                  color: AppColors.error),
              AppSpacing.vGapSm,
              _ExpiringCard(onTap: () => context.pushNamed(RouteNames.products)),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: AppSpacing.screen,
          child: VSButton(
            label: 'Start Shopping',
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
            child: Text('LIMITED TIME',
                style:
                    AppTypography.labelSmall.copyWith(color: AppColors.white)),
          ),
          AppSpacing.vGapSm,
          Text('Up to 60% OFF',
              style:
                  AppTypography.displayMedium.copyWith(color: AppColors.white)),
          Text('On groceries & daily essentials',
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
            child: Text('Shop Now',
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

class _CouponRow extends StatelessWidget {
  const _CouponRow({required this.offer});

  final Offer offer;

  @override
  Widget build(BuildContext context) {
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
              Clipboard.setData(ClipboardData(text: code));
              context.showSnack('Code $code copied');
            },
            child: Text('Apply',
                style: AppTypography.labelLarge
                    .copyWith(color: AppColors.trustBlue)),
          ),
        ],
      ),
    );
  }
}

class _BogoCard extends StatelessWidget {
  const _BogoCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brLg,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: vs.offerTint,
          borderRadius: AppRadius.brLg,
          border: Border.all(color: vs.offer.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: vs.offer,
                borderRadius: AppRadius.brMd,
              ),
              child: const Icon(Icons.redeem_rounded, color: AppColors.white),
            ),
            AppSpacing.hGapMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Buy 1 Get 1 Free', style: AppTypography.titleMedium),
                  Text('On selected snacks & beverages',
                      style: AppTypography.bodySmall
                          .copyWith(color: vs.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: vs.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _MiniDealCard extends StatelessWidget {
  const _MiniDealCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brLg,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: AppRadius.brLg,
          border: Border.all(color: vs.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: AppRadius.brMd,
              ),
              child: Icon(icon, color: color),
            ),
            AppSpacing.vGapMd,
            Text(title, style: AppTypography.titleMedium),
            Text(subtitle,
                style:
                    AppTypography.bodySmall.copyWith(color: vs.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _CashbackCard extends StatelessWidget {
  const _CashbackCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final faint = AppColors.white.withValues(alpha: 0.9);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: const BoxDecoration(
        gradient: AppColors.creditGradient,
        borderRadius: AppRadius.brLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.savings_rounded, color: AppColors.white),
              AppSpacing.hGapSm,
              Text('Pay via VS Credit',
                  style: AppTypography.titleMedium
                      .copyWith(color: AppColors.white)),
            ],
          ),
          AppSpacing.vGapSm,
          Text('5% Flat Cashback',
              style:
                  AppTypography.headlineMedium.copyWith(color: AppColors.white)),
          Text('On all credit purchases this month',
              style: AppTypography.bodySmall.copyWith(color: faint)),
          AppSpacing.vGapMd,
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.white,
                foregroundColor: AppColors.trustBlue,
                elevation: 0,
                shape:
                    const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
              ),
              child: Text('Apply for VS Credit',
                  style: AppTypography.labelLarge
                      .copyWith(color: AppColors.trustBlue)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Expiring-soon promo with a live HH:MM:SS countdown.
class _ExpiringCard extends StatefulWidget {
  const _ExpiringCard({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_ExpiringCard> createState() => _ExpiringCardState();
}

class _ExpiringCardState extends State<_ExpiringCard> {
  Duration _left = const Duration(hours: 2, minutes: 15, seconds: 20);
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
    final vs = context.vsColors;
    final h = _two(_left.inHours);
    final m = _two(_left.inMinutes.remainder(60));
    final s = _two(_left.inSeconds.remainder(60));
    return InkWell(
      onTap: widget.onTap,
      borderRadius: AppRadius.brLg,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: AppRadius.brLg,
          border: Border.all(color: vs.border),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: vs.dangerTint,
                borderRadius: AppRadius.brMd,
              ),
              child: Icon(Icons.eco_rounded, color: vs.danger),
            ),
            AppSpacing.hGapMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Organic Veggie Box',
                      style: AppTypography.titleMedium),
                  Text('₹299 · ends soon',
                      style: AppTypography.bodySmall
                          .copyWith(color: vs.textSecondary)),
                  AppSpacing.vGapXs,
                  Row(
                    children: [
                      _TimeBox(value: h),
                      _Colon(),
                      _TimeBox(value: m),
                      _Colon(),
                      _TimeBox(value: s),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeBox extends StatelessWidget {
  const _TimeBox({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: context.vsColors.danger,
        borderRadius: AppRadius.brXs,
      ),
      child: Text(value,
          style: AppTypography.labelMedium.copyWith(color: AppColors.white)),
    );
  }
}

class _Colon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Text(':',
          style: AppTypography.labelLarge.copyWith(color: context.vsColors.danger)),
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
  const _ErrorRow({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text("Couldn't load coupons.",
              style: AppTypography.bodyMedium),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}
