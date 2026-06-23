import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../address/presentation/providers/address_providers.dart';
import '../../../auth/presentation/providers/session_provider.dart';
import '../../../catalog/presentation/product_navigation.dart';
import '../../domain/services/cart_validation_service.dart';
import '../providers/cart_providers.dart';
import '../widgets/cart_widgets.dart';

/// Shopping cart: validated line items, delivery target, credit upsell, bill
/// summary, and purchase mode. Stock/price validated against the live catalog.
class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  bool _payOnCredit = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(analyticsServiceProvider).track('cart_viewed');
    });
  }

  /// Proceed to checkout — but guests must sign in first (this is the "buy"
  /// moment where login is required).
  void _checkout() {
    final signedIn =
        ref.read(authStatusProvider) == AuthStatus.authenticated;
    if (signedIn) {
      context.pushNamed(RouteNames.checkout);
    } else {
      _promptSignIn();
    }
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
              Text('Sign in to checkout',
                  textAlign: TextAlign.center,
                  style: AppTypography.headlineSmall),
              AppSpacing.vGapSm,
              Text(
                'Create an account or sign in to place your order and pay. '
                'Your cart will be waiting for you.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium
                    .copyWith(color: vs.textSecondary),
              ),
              AppSpacing.vGapLg,
              VSButton(
                label: 'Sign in / Create account',
                onPressed: () {
                  Navigator.of(ctx).pop();
                  context.pushNamed(RouteNames.login);
                },
              ),
              AppSpacing.vGapSm,
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('Keep browsing',
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

    if (cart.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Your Cart')),
        body: VSEmptyCart(onStartShopping: () => context.goNamed(RouteNames.home)),
      );
    }

    final issues = validation.valueOrNull?.issues ?? const <CartIssue>[];
    final warnings = {
      for (final issue in issues) issue.productId: issue.message,
    };
    final hasBlocking = validation.valueOrNull?.hasBlocking ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Cart'),
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
                      onIncrement: () => controller.increment(item.productId),
                      onDecrement: () => controller.decrement(item.productId),
                    ),
                    AppSpacing.vGapSm,
                  ],
                  AppSpacing.vGapSm,
                  const _CreditPromoCard(),
                  AppSpacing.vGapLg,
                  VSCartSummaryCard(summary: summary),
                  AppSpacing.vGapLg,
                  _PurchaseMode(
                    payOnCredit: _payOnCredit,
                    onChanged: (v) => setState(() => _payOnCredit = v),
                  ),
                ],
              ),
            ),
          ),
          VSCartFooter(
            total: summary.total,
            enabled: !hasBlocking,
            onCheckout: _checkout,
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
            child: Text('Some items need attention before checkout.',
                style: AppTypography.labelMedium.copyWith(color: vs.danger)),
          ),
        ],
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
                  address?.formatted ?? 'No address saved yet',
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
            child: Text(address == null ? 'Add' : 'Change'),
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
              Text('VS Credit',
                  style: AppTypography.labelMedium
                      .copyWith(color: AppColors.white)),
            ],
          ),
          AppSpacing.vGapSm,
          Text('Pay later with zero interest.',
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

class _PurchaseMode extends StatelessWidget {
  const _PurchaseMode({required this.payOnCredit, required this.onChanged});

  final bool payOnCredit;
  final ValueChanged<bool> onChanged;

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
          Text('Purchase Mode', style: AppTypography.titleMedium),
          AppSpacing.vGapSm,
          _ModeOption(
            label: 'Pay Now',
            icon: Icons.payments_outlined,
            selected: !payOnCredit,
            onTap: () => onChanged(false),
          ),
          _ModeOption(
            label: 'Buy on Credit',
            icon: Icons.credit_card_rounded,
            selected: payOnCredit,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brMd,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? vs.brand : vs.textSecondary,
            ),
            AppSpacing.hGapMd,
            Expanded(child: Text(label, style: AppTypography.bodyLarge)),
            Icon(icon, color: vs.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }
}
