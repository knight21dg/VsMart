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
import '../../../address/presentation/providers/address_providers.dart';
import '../../../auth/presentation/providers/session_provider.dart';
import '../../../catalog/presentation/product_navigation.dart';
import '../../../offers/presentation/widgets/placement_banner_carousel.dart';
import '../../domain/services/cart_validation_service.dart';
import '../providers/cart_providers.dart';
import '../widgets/cart_widgets.dart';

/// Shopping cart: validated line items, delivery target, credit upsell, bill
/// summary. Stock/price validated against the live catalog. Payment method is
/// chosen at checkout, not here.
class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(analyticsServiceProvider).track('cart_viewed');
    });
  }

  bool _verifyingStock = false;

  /// Proceed to checkout — but guests must sign in first (this is the "buy"
  /// moment where login is required), and every line's stock is re-checked at the
  /// serving store first so an out-of-stock item is caught HERE, not at Pay.
  Future<void> _checkout() async {
    final signedIn =
        ref.read(authStatusProvider) == AuthStatus.authenticated;
    if (!signedIn) {
      _promptSignIn();
      return;
    }
    setState(() => _verifyingStock = true);
    final result = await ref
        .read(cartValidationServiceProvider)
        .validateCart(ref.read(cartControllerProvider));
    if (!mounted) return;
    setState(() => _verifyingStock = false);

    final blocking = result.issues.where((i) => i.isBlocking).toList();
    if (blocking.isNotEmpty) {
      _showStockIssues(blocking);
      return;
    }
    if (mounted) unawaited(context.pushNamed(RouteNames.checkout));
  }

  /// Out-of-stock lines found at checkout — let the shopper remove them and go on,
  /// or go back and adjust. Never silently drops anything.
  void _showStockIssues(List<CartIssue> issues) {
    final vs = context.vsColors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: AppSpacing.screen,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.remove_shopping_cart_outlined, color: vs.danger),
                  AppSpacing.hGapSm,
                  Text(context.l10n.cartItemsUnavailableTitle,
                      style: AppTypography.headlineSmall),
                ],
              ),
              AppSpacing.vGapSm,
              Text(
                context.l10n.cartItemsUnavailableBody,
                style: AppTypography.bodyMedium
                    .copyWith(color: vs.textSecondary),
              ),
              AppSpacing.vGapMd,
              for (final i in issues)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.circle, size: 8, color: vs.danger),
                      AppSpacing.hGapSm,
                      Expanded(
                          child: Text(i.message,
                              style: AppTypography.bodyMedium)),
                    ],
                  ),
                ),
              AppSpacing.vGapLg,
              VSButton(
                label: context.l10n.cartRemoveAndContinue,
                onPressed: () {
                  final controller =
                      ref.read(cartControllerProvider.notifier);
                  for (final i in issues) {
                    controller.remove(i.lineKey);
                  }
                  Navigator.of(ctx).pop();
                  if (ref.read(cartControllerProvider).isNotEmpty) {
                    context.pushNamed(RouteNames.checkout);
                  }
                },
              ),
              AppSpacing.vGapSm,
              VSButton(
                label: context.l10n.cartReviewCart,
                variant: VSButtonVariant.secondary,
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// No delivery address on file yet — send the shopper straight to the
  /// add-address form. When they come back with an address saved, the footer
  /// flips to "Proceed to checkout".
  void _addAddress() {
    unawaited(context.pushNamed(RouteNames.addAddress));
  }

  void _promptSignIn() {
    final vs = context.vsColors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: AppSpacing.screen,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: vs.brandTint,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.lock_outline_rounded, color: vs.brand),
                ),
              ),
              AppSpacing.vGapLg,
              Text(context.l10n.cartSignInToCheckout,
                  textAlign: TextAlign.center,
                  style: AppTypography.headlineSmall),
              AppSpacing.vGapSm,
              Text(
                context.l10n.cartSignInBody,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium
                    .copyWith(color: vs.textSecondary),
              ),
              AppSpacing.vGapLg,
              VSButton(
                label: context.l10n.profileSignInCreate,
                onPressed: () {
                  Navigator.of(ctx).pop();
                  context.pushNamed(RouteNames.login);
                },
              ),
              AppSpacing.vGapSm,
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(context.l10n.cartKeepBrowsing,
                    style: AppTypography.labelLarge
                        .copyWith(color: vs.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartControllerProvider);
    final controller = ref.read(cartControllerProvider.notifier);
    final summary = ref.watch(cartSummaryProvider);
    final connectivity = ref.watch(commerceConnectivityProvider);
    final validation = ref.watch(cartValidationProvider);
    final bill = ref.watch(cartBillProvider);

    // The live bill failed while ONLINE: [cartSummaryProvider] is showing the
    // on-device estimate, which can mismatch the real total. Surface it with a
    // retry rather than passing the estimate off as the authoritative bill.
    // (Offline is handled honestly by the offline banner + estimate.)
    final quoteFailedOnline =
        bill.hasError && connectivity == CommerceConnectivity.online;

    if (cart.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(context.l10n.cartTitle)),
        body: VSEmptyCart(onStartShopping: () => context.goNamed(RouteNames.home)),
      );
    }

    final issues = validation.valueOrNull?.issues ?? const <CartIssue>[];
    final warnings = {
      for (final issue in issues) issue.productId: issue.message,
    };
    final hasBlocking = validation.valueOrNull?.hasBlocking ?? false;

    // When a signed-in shopper has no delivery address yet, the footer becomes
    // an "Add delivery address" CTA (never a greyed-out dead end) that routes to
    // the add-address form; with an address on file it proceeds to checkout.
    final signedIn = ref.watch(authStatusProvider) == AuthStatus.authenticated;
    final needsAddress =
        signedIn && ref.watch(defaultAddressProvider) == null;

    // Below the zone's minimum order value the server will refuse checkout, so
    // the CTA must not promise it. Only trust an authoritative bill: the
    // on-device estimate carries no minimum, and blocking on it would strand a
    // shopper whose zone has none. The "add an address" CTA is never blocked —
    // that step is how they find out which zone (and minimum) applies.
    final belowMinimum =
        !summary.isEstimate && !summary.meetsMinimumOrder && !needsAddress;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.cartTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => context.goNamed(RouteNames.home),
          ),
        ],
      ),
      body: Column(
        children: [
          VSOfflineBanner(
            offline: connectivity == CommerceConnectivity.offline,
            syncing: connectivity == CommerceConnectivity.syncing,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(cartValidationProvider),
              child: ListView(
                padding: AppSpacing.screen,
                children: [
                  if (hasBlocking)
                    _BlockingBanner(),
                  const _DeliverToCard(),
                  AppSpacing.vGapMd,
                  for (final item in cart.items) ...[
                    VSCartItem(
                      item: item,
                      warning: warnings[item.productId],
                      heroTag: detailHeroTag('cart', item.productId),
                      onTap: () => openProductDetail(
                        context,
                        productId: item.productId,
                        source: 'cart',
                      ),
                      // lineKey, not productId: a variant line must be adjustable
                      // on its own (and for a variant-less item they're equal).
                      onIncrement: () => controller.increment(item.lineKey),
                      onDecrement: () => controller.decrement(item.lineKey),
                    ),
                    AppSpacing.vGapSm,
                  ],
                  AppSpacing.vGapSm,
                  const _CreditPromoCard(),
                  AppSpacing.vGapLg,
                  // Marketing slot above the bill — coupon nudges land here.
                  // Renders nothing (and adds no gap) when no banner is live.
                  const PlacementBannerCarousel(
                    placement: 'cart',
                    trailingGap: AppSpacing.lg,
                  ),
                  if (quoteFailedOnline) ...[
                    _QuoteErrorBanner(
                      onRetry: () => ref.invalidate(cartBillProvider),
                    ),
                    AppSpacing.vGapSm,
                  ],
                  VSCartSummaryCard(summary: summary),
                  // The zone's minimum order value. The server refuses a cart
                  // below it, so say so here rather than letting the shopper
                  // reach the payment step and be turned away.
                  if (belowMinimum) ...[
                    AppSpacing.vGapSm,
                    _MinimumOrderBanner(
                      minOrder: summary.minOrder,
                      shortfall: summary.minOrderShortfall,
                    ),
                  ],
                  // Payment method is chosen on checkout, where it is actually
                  // acted on. The cart used to show its own picker whose value
                  // was never passed anywhere — a shopper could select "Buy on
                  // Credit" here and silently be taken down the pay-now path.
                ],
              ),
            ),
          ),
          VSCartFooter(
            total: summary.total,
            label: needsAddress ? 'Add delivery address' : 'Checkout securely',
            icon: needsAddress
                ? Icons.add_location_alt_rounded
                : Icons.arrow_forward_rounded,
            // The add-address CTA stays live even when stock issues exist — the
            // shopper resolves the address here, then returns to fix any lines.
            enabled: needsAddress
                ? !_verifyingStock
                : (!hasBlocking && !_verifyingStock && !belowMinimum),
            onCheckout: needsAddress ? _addAddress : _checkout,
          ),
        ],
      ),
    );
  }
}

class _BlockingBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: vs.dangerTint,
        borderRadius: AppRadius.brMd,
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: vs.danger),
          AppSpacing.hGapSm,
          Expanded(
            child: Text(context.l10n.cartItemsNeedAttention,
                style: AppTypography.labelMedium.copyWith(color: vs.danger)),
          ),
        ],
      ),
    );
  }
}

/// The cart hasn't reached the serving zone's minimum order value.
///
/// The checkout CTA is disabled alongside this, so the banner has to carry the
/// whole explanation — the threshold *and* the exact amount still needed. A
/// greyed-out button with no reason is the failure mode this replaces.
class _MinimumOrderBanner extends StatelessWidget {
  const _MinimumOrderBanner({required this.minOrder, required this.shortfall});

  final num minOrder;
  final num shortfall;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: vs.offerTint,
        borderRadius: AppRadius.brMd,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shopping_basket_outlined, size: 18, color: vs.warning),
          AppSpacing.hGapSm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Minimum order is ${minOrder.asCurrency}',
                  style: AppTypography.labelMedium.copyWith(color: vs.warning),
                ),
                Text(
                  'Add ${shortfall.asCurrency} more to place this order.',
                  style: AppTypography.bodySmall
                      .copyWith(color: context.vsColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when the authoritative `/cart/quote` bill fails while online. The cart
/// keeps rendering the on-device estimate, but this makes clear it isn't the
/// live total and offers a one-tap retry (invalidates [cartBillProvider]).
class _QuoteErrorBanner extends StatelessWidget {
  const _QuoteErrorBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      onTap: onRetry,
      borderRadius: AppRadius.brMd,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: vs.offerTint,
          borderRadius: AppRadius.brMd,
        ),
        child: Row(
          children: [
            Icon(Icons.receipt_long_outlined, size: 18, color: vs.warning),
            AppSpacing.hGapSm,
            Expanded(
              child: Text(
                context.l10n.cartTotalEstimateError,
                style:
                    AppTypography.labelMedium.copyWith(color: vs.warning),
              ),
            ),
            AppSpacing.hGapSm,
            Icon(Icons.refresh_rounded, size: 18, color: vs.warning),
          ],
        ),
      ),
    );
  }
}

class _DeliverToCard extends ConsumerWidget {
  const _DeliverToCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    final address = ref.watch(defaultAddressProvider);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
      ),
      child: Row(
        children: [
          Icon(Icons.location_on_rounded, color: vs.brand),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  address == null
                      ? 'Add a delivery address'
                      : 'Deliver to ${address.name}',
                  style: AppTypography.titleMedium,
                ),
                Text(
                  address?.formatted ?? context.l10n.addressNone,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      AppTypography.bodySmall.copyWith(color: vs.textSecondary),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => context.pushNamed(RouteNames.addresses),
            child: Text(address == null ? context.l10n.commonAdd : context.l10n.commonChange),
          ),
        ],
      ),
    );
  }
}

class _CreditPromoCard extends StatelessWidget {
  const _CreditPromoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: const BoxDecoration(
        gradient: AppColors.greenGradient,
        borderRadius: AppRadius.brLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt_rounded, color: AppColors.white, size: 18),
              AppSpacing.hGapSm,
              Text(context.l10n.checkoutVsCredit,
                  style: AppTypography.labelMedium
                      .copyWith(color: AppColors.white)),
            ],
          ),
          AppSpacing.vGapSm,
          Text(context.l10n.cartPayLaterZeroInterest,
              style: AppTypography.titleLarge.copyWith(color: AppColors.white)),
          const SizedBox(height: 2),
          Text('Get up to ₹10,000 instant credit line for your daily needs.',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.white.withValues(alpha: 0.9))),
        ],
      ),
    );
  }
}

