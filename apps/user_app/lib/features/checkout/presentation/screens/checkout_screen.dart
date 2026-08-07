import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/app_error_presenter.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../address/presentation/providers/address_selection_provider.dart';
import '../../../cart/presentation/providers/cart_providers.dart';
import '../../../catalog/presentation/product_navigation.dart';
import '../../../credit/domain/credit_access.dart';
import '../../../credit/presentation/providers/credit_access_provider.dart';
import '../../../credit/presentation/providers/credit_providers.dart';
import '../../../credit/presentation/widgets/credit_apply_card.dart';
import '../../../orders/domain/entities/order.dart';
import '../../../orders/domain/entities/order_enums.dart';
import '../../../serviceability/presentation/providers/serviceability_providers.dart';
import '../../domain/credit_repayment_plan.dart';
import '../providers/checkout_controller.dart';
import '../widgets/credit_checkout_widgets.dart';

/// Checkout: confirm address, slot, coupon, payment, and place the order. Pure
/// orchestration over [checkoutControllerProvider] + cart/address/credit.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _coupon = TextEditingController();

  static const _slots = [
    ('Express', '30 min'),
    ('Today', '6–8 PM'),
    ('Tomorrow', '9–11 AM'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(analyticsServiceProvider).track('checkout_started');
      _maybeApplyPendingCoupon();
    });
  }

  /// Auto-applies a coupon carried in from Offers / the Coupons wallet. Runs the
  /// SAME server validation as a manually typed coupon (so an invalid/expired
  /// carried code is surfaced honestly), pre-fills the field, and consumes the
  /// pending code so it applies once. Never overrides a coupon the shopper has
  /// already applied on this screen.
  Future<void> _maybeApplyPendingCoupon() async {
    final pending = ref.read(pendingCouponProvider);
    if (pending == null || pending.isEmpty) return;
    ref.read(pendingCouponProvider.notifier).state = null;
    if (ref.read(checkoutControllerProvider).coupon != null) return;
    _coupon.text = pending;
    final result = await _controller.applyCoupon(pending);
    if (!mounted) return;
    final failure = result.failure;
    if (failure != null) {
      presentFailure(context, ref, failure);
    } else {
      context.showSnack(result.message, isError: !result.valid);
    }
  }

  @override
  void dispose() {
    _coupon.dispose();
    super.dispose();
  }

  CheckoutController get _controller =>
      ref.read(checkoutControllerProvider.notifier);

  Future<void> _placeOrder() async {
    final order = await _controller.placeOrder();
    if (!mounted) return;
    if (order != null) {
      // The order is now placed. For online methods (UPI/Card) it is still
      // UNPAID until the gateway settles, so charge it before declaring success;
      // COD and VS Credit need no gateway and go straight through.
      await _settlePaymentAndFinish(order);
      return;
    }
    // Surface the specific backend reason (out of stock, credit ineligible,
    // KYC required, etc.) when we have it, instead of a generic message.
    final failure = ref.read(checkoutControllerProvider).error;
    if (failure == null) {
      // Blocked by a local precondition (empty cart, terms) with no failure set.
      context.showSnack(context.l10n.checkoutCouldNotPlaceOrder,
          isError: true);
      return;
    }
    // The serviceability gate is a locally-built failure carrying no navigate
    // action, so keep the bespoke "Change address" snackbar the presenter
    // couldn't reproduce.
    if (failure.code == kNotServiceableCode) {
      context.messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(failure.message),
            backgroundColor: context.vsColors.danger,
            action: SnackBarAction(
              label: context.l10n.checkoutChangeAddress,
              textColor: context.colors.onError,
              onPressed: () => context.pushNamed(RouteNames.addresses),
            ),
          ),
        );
      return;
    }
    // Route actionable backend codes through the central presenter so
    // navigate/logout/retry/dialog fire (e.g. KYC_REQUIRED navigates to KYC).
    presentFailure(context, ref, failure, onRetry: _placeOrder);
  }

  /// After the order is placed, settle its payment (UPI/Card open Razorpay via
  /// [CheckoutController.settleOrderPayment]; COD/VS Credit are a no-op success),
  /// then route to the success screen. On a failed or cancelled online payment
  /// the order EXISTS but is unpaid — so DON'T show success. Keep the user here
  /// and offer a Retry that re-runs settlement for the SAME order; it reuses the
  /// `pay_order_<id>` idempotency key, so no duplicate charge is created.
  Future<void> _settlePaymentAndFinish(Order order) async {
    final paid = await _controller.settleOrderPayment(order);
    if (!mounted) return;
    if (paid) {
      context.pushReplacementNamed(RouteNames.orderSuccess);
      return;
    }
    context.messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(context.l10n.paymentNotCompleted),
          backgroundColor: context.vsColors.danger,
          action: SnackBarAction(
            label: context.l10n.commonRetry,
            textColor: context.colors.onError,
            onPressed: () => _settlePaymentAndFinish(order),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final state = ref.watch(checkoutControllerProvider);
    final cart = ref.watch(cartControllerProvider);
    // Checkout uses the coupon-adjusted bill (the quote is re-run server-side
    // with the coupon), so [summary.total] already has the discount applied —
    // no local subtraction. The cart screen keeps the coupon-free summary.
    final summary = ref.watch(checkoutSummaryProvider);
    final address = ref.watch(selectedAddressProvider);
    final access = ref.watch(creditAccessProvider);
    // Only an active credit line exposes real figures — no leak to non-applicants.
    final account = access.isActive
        ? ref.watch(creditAccountProvider).valueOrNull
        : null;
    final validation = ref.watch(cartValidationProvider);
    final total = summary.total;

    final isCredit = state.paymentMethod == PaymentMethod.credit;
    // A credit order needs an ACTIVE credit line with enough headroom; a customer
    // who hasn't applied can never place one.
    final creditOk = !isCredit ||
        (access.isActive && (account?.available ?? 0) >= total);
    final blocking = validation.valueOrNull?.hasBlocking ?? false;
    // Zone/store gate: the serving store must be serviceable, open, and under its
    // daily capacity — otherwise the backend rejects the order, so block it here
    // proactively and tell the customer why.
    final svc = ref.watch(currentServiceabilityProvider);
    final serviceabilityBlock = svc.blockedReason;
    final canPlace = cart.isNotEmpty &&
        address != null &&
        creditOk &&
        !blocking &&
        svc.canCheckout &&
        !state.placing;

    return Scaffold(
      appBar: VSAppBar(title: context.l10n.checkoutTitle),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: AppSpacing.screen,
              children: [
                _Section(
                  title: context.l10n.checkoutDeliveryAddress,
                  trailing: TextButton(
                    onPressed: () => context.pushNamed(RouteNames.addresses),
                    child: Text(address == null ? 'Select' : context.l10n.commonChange),
                  ),
                  child: address == null
                      ? Text(context.l10n.checkoutSelectAddress,
                          style: AppTypography.bodyMedium
                              .copyWith(color: vs.textSecondary))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(address.name,
                                style: AppTypography.labelLarge),
                            Text(address.formatted,
                                style: AppTypography.bodySmall
                                    .copyWith(color: vs.textSecondary)),
                            if (address.phone.isNotEmpty)
                              Text(address.phone,
                                  style: AppTypography.bodySmall
                                      .copyWith(color: vs.textSecondary)),
                          ],
                        ),
                ),
                AppSpacing.vGapMd,
                _Section(
                  title: context.l10n.orderSummary,
                  child: Column(
                    children: [
                      for (final item in cart.items)
                        Builder(builder: (context) {
                          final heroTag =
                              detailHeroTag('checkout', item.productId);
                          return InkWell(
                          onTap: () => openProductDetail(
                            context,
                            productId: item.productId,
                            source: 'checkout',
                          ),
                          borderRadius: AppRadius.brSm,
                          child: Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: AppRadius.brSm,
                                  child: Container(
                                    height: 44,
                                    width: 44,
                                    color: vs.brandTint,
                                    child: Hero(
                                      tag: heroTag,
                                      flightShuttleBuilder:
                                          (_, __, ___, ____, _____) =>
                                              VSNetworkImage(
                                        url: item.imageUrl,
                                        fit: BoxFit.cover,
                                        fallbackIcon:
                                            Icons.shopping_basket_rounded,
                                      ),
                                      child: VSNetworkImage(
                                        url: item.imageUrl,
                                        fit: BoxFit.cover,
                                        borderRadius: AppRadius.brSm,
                                        fallbackIcon:
                                            Icons.shopping_basket_rounded,
                                      ),
                                    ),
                                  ),
                                ),
                                AppSpacing.hGapMd,
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(item.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTypography.bodyMedium),
                                      Text(context.l10n.checkoutQty(item.quantity),
                                          style: AppTypography.labelSmall
                                              .copyWith(
                                                  color: vs.textSecondary)),
                                    ],
                                  ),
                                ),
                                Text(item.lineTotal.asCurrency,
                                    style: AppTypography.labelLarge),
                              ],
                            ),
                          ),
                        );
                        }),
                    ],
                  ),
                ),
                AppSpacing.vGapMd,
                _Section(
                  title: context.l10n.checkoutDeliverySlot,
                  child: Row(
                    children: [
                      for (var i = 0; i < _slots.length; i++) ...[
                        Expanded(
                          child: _SlotChip(
                            label: _slots[i].$1,
                            sub: _slots[i].$2,
                            selected: state.deliverySlot == i,
                            onTap: () => _controller.setDeliverySlot(i),
                          ),
                        ),
                        if (i < _slots.length - 1) AppSpacing.hGapSm,
                      ],
                    ],
                  ),
                ),
                AppSpacing.vGapMd,
                _CouponField(
                  controller: _coupon,
                  applied: state.coupon,
                  discount: state.couponDiscount,
                  onApply: () async {
                    context.hideKeyboard();
                    final result = await _controller.applyCoupon(_coupon.text);
                    if (!context.mounted) return;
                    // A transport/server error carries a typed failure -> route
                    // it through the presenter; a plain "invalid coupon" verdict
                    // stays a lightweight snackbar.
                    final failure = result.failure;
                    if (failure != null) {
                      presentFailure(context, ref, failure);
                    } else {
                      context.showSnack(result.message, isError: !result.valid);
                    }
                  },
                  onRemove: () {
                    _controller.removeCoupon();
                    _coupon.clear();
                  },
                ),
                AppSpacing.vGapMd,
                _Section(
                  title: context.l10n.checkoutPaymentMethod,
                  child: Column(
                    children: [
                      _PayModeToggle(
                        payOnCredit: isCredit,
                        onPayNow: () {
                          if (isCredit) {
                            _controller.selectPaymentMethod(
                                PaymentMethod.cashOnDelivery);
                          }
                        },
                        onPayOnCredit: () => _controller
                            .selectPaymentMethod(PaymentMethod.credit),
                      ),
                      AppSpacing.vGapMd,
                      if (!isCredit) ...[
                        // Pay Now → online payment + cash on delivery only.
                        _PayOptionTile(
                          icon: Icons.account_balance_wallet_rounded,
                          title: context.l10n.checkoutOnlinePayment,
                          subtitle: context.l10n.checkoutUpiCardsNetbanking,
                          selected:
                              state.paymentMethod == PaymentMethod.upi,
                          onTap: () => _controller
                              .selectPaymentMethod(PaymentMethod.upi),
                        ),
                        AppSpacing.vGapSm,
                        _PayOptionTile(
                          icon: Icons.payments_outlined,
                          title: context.l10n.checkoutCod,
                          subtitle: context.l10n.checkoutPayOnArrival,
                          selected: state.paymentMethod ==
                              PaymentMethod.cashOnDelivery,
                          onTap: () => _controller.selectPaymentMethod(
                              PaymentMethod.cashOnDelivery),
                        ),
                      ] else if (!access.isActive) ...[
                        // Pay on Credit but not approved → apply prompt only.
                        CreditApplyCard(access: access, dense: true),
                      ] else ...[
                        // Pay on Credit → VS Credit only + repayment plan.
                        _PayOptionTile(
                          icon: Icons.account_balance_rounded,
                          title: context.l10n.checkoutVsCredit,
                          subtitle: context.l10n.checkoutBuyNowPayLater,
                          selected: true,
                          onTap: () {},
                        ),
                        AppSpacing.vGapMd,
                        VSCreditEligibilityBanner(
                          available: account?.available ?? 0,
                          amount: total,
                        ),
                        AppSpacing.vGapMd,
                        VSCreditCheckoutCard(
                          creditLimit: account?.creditLimit ?? 0,
                          outstanding: account?.outstanding ?? 0,
                          purchaseAmount: total,
                        ),
                        AppSpacing.vGapMd,
                        _RepaymentPlanSelector(
                          selected: state.creditPlan,
                          onSelect: _controller.selectCreditPlan,
                        ),
                        AppSpacing.vGapMd,
                        _PayoutDateRow(plan: state.creditPlan),
                      ],
                    ],
                  ),
                ),
                AppSpacing.vGapMd,
                _Section(
                  title: context.l10n.checkoutBillSummary,
                  child: Column(
                    children: [
                      _SummaryRow(context.l10n.checkoutItemTotal, summary.subtotal.asCurrency),
                      AppSpacing.vGapSm,
                      _SummaryRow(
                          context.l10n.cartDeliveryFee,
                          summary.deliveryCharges == 0
                              ? context.l10n.cartFree
                              : summary.deliveryCharges.asCurrency),
                      AppSpacing.vGapSm,
                      _SummaryRow(context.l10n.cartGst, summary.gstAmount.asCurrency),
                      // Discount straight from the server-computed bill so the
                      // line and the grand total below always reconcile.
                      if (summary.couponDiscount > 0) ...[
                        AppSpacing.vGapSm,
                        _SummaryRow('Coupon Discount',
                            '- ${summary.couponDiscount.asCurrency}'),
                      ],
                      const Divider(height: AppSpacing.xl),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(context.l10n.checkoutGrandTotal, style: AppTypography.titleLarge),
                          Text(total.asCurrency, style: AppTypography.priceLarge),
                        ],
                      ),
                    ],
                  ),
                ),
                AppSpacing.vGapMd,
                const _TermsNote(),
              ],
            ),
          ),
          if (address != null && serviceabilityBlock != null)
            _ServiceabilityNotice(message: serviceabilityBlock),
          _CheckoutBar(
            total: total,
            placing: state.placing,
            enabled: canPlace,
            label: state.paymentMethod == PaymentMethod.credit
                ? 'Pay on Credit'
                : context.l10n.checkoutPlaceOrder,
            onPressed: _placeOrder,
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: AppTypography.titleMedium),
              if (trailing != null) trailing!,
            ],
          ),
          AppSpacing.vGapSm,
          child,
        ],
      ),
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({
    required this.label,
    required this.sub,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brMd,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? vs.brandTint : context.colors.surface,
          borderRadius: AppRadius.brMd,
          border: Border.all(color: selected ? vs.brand : vs.border),
        ),
        child: Column(
          children: [
            Text(label,
                style: AppTypography.labelMedium.copyWith(
                  color: selected ? vs.brand : null,
                  fontWeight: FontWeight.w700,
                )),
            Text(sub,
                style:
                    AppTypography.labelSmall.copyWith(color: vs.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _CouponField extends StatelessWidget {
  const _CouponField({
    required this.controller,
    required this.applied,
    required this.discount,
    required this.onApply,
    required this.onRemove,
  });

  final TextEditingController controller;
  final String? applied;
  final num discount;
  final VoidCallback onApply;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    if (applied != null && discount > 0) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
            color: vs.successTint, borderRadius: AppRadius.brLg),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, size: 18, color: vs.success),
            AppSpacing.hGapMd,
            Expanded(
              child: Text(
                  context.l10n
                      .checkoutCouponAppliedOff(applied!, discount.asCurrency),
                  style: AppTypography.labelMedium.copyWith(color: vs.success)),
            ),
            GestureDetector(
              onTap: onRemove,
              child: Text(context.l10n.commonRemove,
                  style: AppTypography.labelMedium.copyWith(color: vs.danger)),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
      ),
      child: Row(
        children: [
          Icon(Icons.local_offer_outlined, size: 20, color: vs.offer),
          AppSpacing.hGapSm,
          Expanded(
            child: TextField(
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: context.l10n.checkoutApplyCoupon,
                border: InputBorder.none,
              ),
            ),
          ),
          TextButton(onPressed: onApply, child: Text(context.l10n.commonApply)),
        ],
      ),
    );
  }
}

/// Segmented "Pay Now" vs "Pay on Credit" switch at the top of the payment
/// section.
class _PayModeToggle extends StatelessWidget {
  const _PayModeToggle({
    required this.payOnCredit,
    required this.onPayNow,
    required this.onPayOnCredit,
  });

  final bool payOnCredit;
  final VoidCallback onPayNow;
  final VoidCallback onPayOnCredit;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: vs.brandTint.withValues(alpha: 0.5),
        borderRadius: AppRadius.brPill,
        border: Border.all(color: vs.border),
      ),
      child: Row(
        children: [
          Expanded(
              child: _seg(context, context.l10n.checkoutPayNow, !payOnCredit, onPayNow)),
          Expanded(
              child: _seg(
                  context, 'Pay on Credit', payOnCredit, onPayOnCredit)),
        ],
      ),
    );
  }

  Widget _seg(
      BuildContext context, String label, bool active, VoidCallback onTap) {
    final vs = context.vsColors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? vs.brand : Colors.transparent,
          borderRadius: AppRadius.brPill,
        ),
        child: Text(
          label,
          style: AppTypography.labelLarge.copyWith(
            color: active ? AppColors.white : vs.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// A single payment option row (online / COD / VS Credit).
class _PayOptionTile extends StatelessWidget {
  const _PayOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brMd,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? vs.trustTint : context.colors.surface,
          borderRadius: AppRadius.brMd,
          border: Border.all(color: selected ? vs.trust : vs.border),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? vs.trust : vs.textSecondary,
            ),
            AppSpacing.hGapMd,
            Icon(icon, color: vs.textSecondary, size: 22),
            AppSpacing.hGapMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.bodyLarge),
                  Text(subtitle,
                      style: AppTypography.bodySmall
                          .copyWith(color: vs.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Weekend vs Month-End repayment choice for a VS Credit purchase.
class _RepaymentPlanSelector extends StatelessWidget {
  const _RepaymentPlanSelector({required this.selected, required this.onSelect});

  final CreditRepaymentPlan selected;
  final ValueChanged<CreditRepaymentPlan> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l10n.checkoutChooseRepaymentPlan,
            style: AppTypography.labelLarge),
        AppSpacing.vGapSm,
        Row(
          children: [
            for (final plan in CreditRepaymentPlan.values) ...[
              Expanded(
                child: _PlanTile(
                  plan: plan,
                  selected: selected == plan,
                  onTap: () => onSelect(plan),
                ),
              ),
              if (plan != CreditRepaymentPlan.values.last) AppSpacing.hGapSm,
            ],
          ],
        ),
      ],
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  final CreditRepaymentPlan plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final date = DateFormat('d MMM').format(plan.payoutDate());
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brMd,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? vs.trustTint : context.colors.surface,
          borderRadius: AppRadius.brMd,
          border: Border.all(
              color: selected ? vs.trust : vs.border,
              width: selected ? 1.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 18,
                  color: selected ? vs.trust : vs.textSecondary,
                ),
                AppSpacing.hGapSm,
                Expanded(
                  child: Text(plan.label,
                      style: AppTypography.labelMedium.copyWith(
                        color: selected ? vs.trust : null,
                        fontWeight: FontWeight.w700,
                      )),
                ),
              ],
            ),
            AppSpacing.vGapXs,
            Text(context.l10n.checkoutDueDate(date),
                style: AppTypography.bodySmall
                    .copyWith(color: vs.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// Prominent payout-date callout beneath the repayment plan.
class _PayoutDateRow extends StatelessWidget {
  const _PayoutDateRow({required this.plan});

  final CreditRepaymentPlan plan;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final date = DateFormat('EEEE, d MMMM').format(plan.payoutDate());
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: vs.trustTint,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: vs.trust.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.event_available_rounded, size: 20, color: vs.trust),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.checkoutPayoutDate,
                    style: AppTypography.labelSmall
                        .copyWith(color: vs.textSecondary)),
                Text(date,
                    style: AppTypography.labelLarge.copyWith(color: vs.trust)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TermsNote extends StatelessWidget {
  const _TermsNote();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Row(
      children: [
        Icon(Icons.info_outline_rounded, size: 16, color: vs.textSecondary),
        AppSpacing.hGapSm,
        Expanded(
          child: Text(context.l10n.checkoutAgreeTerms,
              style: AppTypography.bodySmall.copyWith(color: vs.textSecondary)),
        ),
      ],
    );
  }
}

/// A strip above the checkout bar explaining why the order can't be placed right
/// now — store closed, at capacity, or the address fell outside coverage.
class _ServiceabilityNotice extends StatelessWidget {
  const _ServiceabilityNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      width: double.infinity,
      color: vs.dangerTint,
      padding: AppSpacing.screen,
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: vs.danger),
          AppSpacing.hGapSm,
          Expanded(
            child: Text(message,
                style: AppTypography.bodySmall.copyWith(color: vs.danger)),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary)),
        Text(value, style: AppTypography.labelLarge),
      ],
    );
  }
}

class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({
    required this.total,
    required this.placing,
    required this.enabled,
    required this.label,
    required this.onPressed,
  });

  final num total;
  final bool placing;
  final bool enabled;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: vs.border)),
      ),
      child: SafeArea(
        minimum: AppSpacing.screen,
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.l10n.cartTotal,
                    style: AppTypography.bodySmall
                        .copyWith(color: vs.textSecondary)),
                Text(total.asCurrency, style: AppTypography.priceMedium),
              ],
            ),
            AppSpacing.hGapLg,
            Expanded(
              child: VSButton(
                label: label,
                isLoading: placing,
                onPressed: enabled ? onPressed : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
