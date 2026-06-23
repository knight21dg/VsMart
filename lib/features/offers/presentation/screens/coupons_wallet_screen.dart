import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/coupon.dart';
import '../providers/coupon_wallet_provider.dart';

/// Coupons & Offers — a rich, image-driven coupons wallet (Zepto-style): a
/// savings hero, ticket-style coupon cards with the real terms (discount, min
/// order, cap, validity), tap-to-copy codes, and a "how to use" helper.
class CouponsWalletScreen extends ConsumerWidget {
  const CouponsWalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coupons = ref.watch(couponWalletProvider);
    return Scaffold(
      appBar: const VSAppBar(title: 'Coupons & Offers'),
      body: SafeArea(
        top: false,
        child: coupons.when(
          loading: () => const _LoadingView(),
          error: (_, __) => VSErrorView(
            message: "Couldn't load your coupons.",
            onRetry: () => ref.invalidate(couponWalletProvider),
          ),
          data: (items) => RefreshIndicator(
            onRefresh: () async => ref.invalidate(couponWalletProvider),
            child: _Loaded(coupons: items),
          ),
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xxl),
      children: const [
        VSShimmerBox(height: 150, borderRadius: AppRadius.brXl),
        AppSpacing.vGapLg,
        VSShimmerBox(height: 150, borderRadius: AppRadius.brLg),
        AppSpacing.vGapMd,
        VSShimmerBox(height: 150, borderRadius: AppRadius.brLg),
      ],
    );
  }
}

class _Loaded extends StatelessWidget {
  const _Loaded({required this.coupons});

  final List<Coupon> coupons;

  @override
  Widget build(BuildContext context) {
    final active = coupons.where((c) => !c.isExpired).toList();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.lg),
      children: [
        _SavingsHero(count: active.length),
        AppSpacing.vGapLg,
        if (active.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.huge),
            child: VSEmptyState(
              icon: Icons.confirmation_number_outlined,
              title: 'No coupons yet',
              message: 'Coupons you collect will appear here.',
            ),
          )
        else ...[
          Text('Available Coupons', style: AppTypography.titleLarge),
          AppSpacing.vGapMd,
          for (var i = 0; i < active.length; i++) ...[
            _CouponTicket(coupon: active[i], paletteIndex: i),
            if (i != active.length - 1) AppSpacing.vGapMd,
          ],
          AppSpacing.vGapLg,
          const _HowToUseCard(),
        ],
        const VSLoveFooter(),
      ],
    );
  }
}

/// Orange savings hero with a coupon illustration motif.
class _SavingsHero extends StatelessWidget {
  const _SavingsHero({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final faint = AppColors.white.withValues(alpha: 0.92);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: AppColors.offerGradient,
        borderRadius: AppRadius.brXl,
        boxShadow: AppShadows.glow(AppColors.offerOrange),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Save more on every order',
                    style: AppTypography.headlineSmall
                        .copyWith(color: AppColors.white)),
                AppSpacing.vGapXs,
                Text(
                  count == 0
                      ? 'Collect coupons and apply them at checkout.'
                      : '$count coupon${count == 1 ? '' : 's'} ready to use at checkout.',
                  style: AppTypography.bodySmall.copyWith(color: faint),
                ),
              ],
            ),
          ),
          AppSpacing.hGapMd,
          Container(
            height: 64,
            width: 64,
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.confirmation_number_rounded,
                color: AppColors.white, size: 34),
          ),
        ],
      ),
    );
  }
}

/// A ticket-style coupon card: a coloured left panel with the discount, a
/// perforation, then the code + terms + copy action.
class _CouponTicket extends StatelessWidget {
  const _CouponTicket({required this.coupon, required this.paletteIndex});

  final Coupon coupon;
  final int paletteIndex;

  static const _palettes = [
    AppColors.greenGradient,
    AppColors.creditGradient,
    AppColors.offerGradient,
  ];

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: coupon.code));
    context.showSnack('Code ${coupon.code} copied — apply it at checkout');
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final gradient = _palettes[paletteIndex % _palettes.length];
    final faint = AppColors.white.withValues(alpha: 0.9);
    return InkWell(
      onTap: () => _copy(context),
      borderRadius: AppRadius.brLg,
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: AppRadius.brLg,
          border: Border.all(color: vs.border),
          boxShadow: AppShadows.xs,
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Discount panel.
              Container(
                width: 104,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(gradient: gradient),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(coupon.headline,
                        textAlign: TextAlign.center,
                        style: AppTypography.titleLarge
                            .copyWith(color: AppColors.white)),
                    const SizedBox(height: 2),
                    Text(coupon.subline,
                        textAlign: TextAlign.center,
                        style: AppTypography.labelSmall.copyWith(color: faint)),
                  ],
                ),
              ),
              // Perforation.
              const _Perforation(),
              // Details.
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _CodeChip(code: coupon.code, onCopy: () => _copy(context)),
                      AppSpacing.vGapSm,
                      _InfoLine(
                          icon: Icons.shopping_bag_outlined,
                          text: coupon.minOrderLabel),
                      const SizedBox(height: 4),
                      _InfoLine(
                          icon: Icons.schedule_rounded,
                          text: coupon.validityLabel),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dashed vertical perforation between the discount panel and details.
class _Perforation extends StatelessWidget {
  const _Perforation();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return SizedBox(
      width: 14,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(
          9,
          (_) => Container(
            height: 4,
            width: 2,
            decoration: BoxDecoration(
              color: vs.border,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    );
  }
}

class _CodeChip extends StatelessWidget {
  const _CodeChip({required this.code, required this.onCopy});

  final String code;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: 6),
            decoration: BoxDecoration(
              color: vs.brandTint.withValues(alpha: 0.6),
              borderRadius: AppRadius.brSm,
              border: Border.all(
                  color: vs.brand.withValues(alpha: 0.4),
                  style: BorderStyle.solid),
            ),
            child: Text(code,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.titleMedium
                    .copyWith(color: vs.brand, letterSpacing: 0.5)),
          ),
        ),
        AppSpacing.hGapSm,
        GestureDetector(
          onTap: onCopy,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.copy_rounded, size: 15, color: vs.brand),
              const SizedBox(width: 2),
              Text('COPY',
                  style: AppTypography.labelMedium.copyWith(
                      color: vs.brand, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Row(
      children: [
        Icon(icon, size: 14, color: vs.textSecondary),
        AppSpacing.hGapSm,
        Expanded(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  AppTypography.bodySmall.copyWith(color: vs.textSecondary)),
        ),
      ],
    );
  }
}

/// Short "how to use" helper at the bottom of the wallet.
class _HowToUseCard extends StatelessWidget {
  const _HowToUseCard();

  static const _steps = [
    (Icons.touch_app_rounded, 'Tap a coupon to copy its code'),
    (Icons.add_shopping_cart_rounded, 'Add items to your cart'),
    (Icons.local_offer_rounded, 'Paste the code at checkout to save'),
  ];

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How to use a coupon', style: AppTypography.titleMedium),
          AppSpacing.vGapMd,
          for (var i = 0; i < _steps.length; i++) ...[
            Row(
              children: [
                Container(
                  height: 32,
                  width: 32,
                  decoration:
                      BoxDecoration(color: vs.brandTint, shape: BoxShape.circle),
                  child: Icon(_steps[i].$1, size: 17, color: vs.brand),
                ),
                AppSpacing.hGapMd,
                Expanded(
                    child: Text(_steps[i].$2, style: AppTypography.bodyMedium)),
              ],
            ),
            if (i != _steps.length - 1) AppSpacing.vGapMd,
          ],
        ],
      ),
    );
  }
}
