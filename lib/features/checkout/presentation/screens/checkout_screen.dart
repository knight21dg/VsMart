import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../address/presentation/providers/address_selection_provider.dart';
import '../../../cart/presentation/providers/cart_providers.dart';
import '../../../credit/domain/credit_access.dart';
import '../../../credit/presentation/providers/credit_access_provider.dart';
import '../../../credit/presentation/providers/credit_providers.dart';
import '../../../credit/presentation/widgets/credit_apply_card.dart';
import '../../../orders/domain/entities/order_enums.dart';
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
    });
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
      context.pushReplacementNamed(RouteNames.orderSuccess);
    } else {
      // Surface the specific backend reason (out of stock, credit ineligible,
      // etc.) when we have it, instead of a generic message.
      final failure = ref.read(checkoutControllerProvider).error;
      context.showSnack(
        failure?.message ?? 'Could not place order. Please review your cart.',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final state = ref.watch(checkoutControllerProvider);
    final cart = ref.watch(cartControllerProvider);
    final summary = ref.watch(cartSummaryProvider);
    final address = ref.watch(selectedAddressProvider);
    final access = ref.watch(creditAccessProvider);
    // Only an active credit line exposes real figures — no leak to non-applicants.
    final account = access.isActive
        ? ref.watch(creditAccountProvider).valueOrNull
        : null;
    final validation = ref.watch(cartValidationProvider);
    final total = summary.total - state.couponDiscount;

    final isCredit = state.paymentMethod == PaymentMethod.credit;
    // A credit order needs an ACTIVE credit line with enough headroom; a customer
    // who hasn't applied can never place one.
    final creditOk = !isCredit ||
        (access.isActive && (account?.available ?? 0) >= total);
    final blocking = validation.valueOrNull?.hasBlocking ?? false;
    final canPlace = cart.isNotEmpty &&
        address != null &&
        creditOk &&
        !blocking &&
        !state.placing;

    return Scaffold(
      appBar: const VSAppBar(title: 'Checkout'),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: AppSpacing.screen,
              children: [
                _Section(
                  title: 'Delivery Address',
                  trailing: TextButton(
                    onPressed: () => context.pushNamed(RouteNames.addresses),
                    child: Text(address == null ? 'Select' : 'Change'),
                  ),
                  child: address == null
                      ? Text('No delivery address selected',
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
                  title: 'Order Summary',
                  child: Column(
                    children: [
                      for (final item in cart.items)
                        InkWell(
                          onTap: () => context.pushNamed(
                            RouteNames.productDetails,
                            pathParameters: {'productId': item.productId},
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
                                    child: VSNetworkImage(
                                      url: item.imageUrl,
                                      fit: BoxFit.cover,
                                      borderRadius: AppRadius.brSm,
                                      fallbackIcon:
                                          Icons.shopping_basket_rounded,
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
                                      Text('Qty ${item.quantity}',
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
                        ),
                    ],
                  ),
                ),
                AppSpacing.vGapMd,
                _Section(
                  title: 'Delivery Slot',
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
                    if (context.mounted) {
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
                  title: 'Payment Method',
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
                          title: 'Online Payment',
                          subtitle: 'UPI, cards & net banking',
                          selected:
                              state.paymentMethod == PaymentMethod.upi,
                          onTap: () => _controller
                              .selectPaymentMethod(PaymentMethod.upi),
                        ),
                        AppSpacing.vGapSm,
                        _PayOptionTile(
                          icon: Icons.payments_outlined,
                          title: 'Cash on Delivery',
                          subtitle: 'Pay when your order arrives',
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
                          title: 'VS Credit',
                          subtitle: 'Buy now, pay later',
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
                  title: 'Bill Summary',
                  child: Column(
                    children: [
                      _SummaryRow('Item Total', summary.subtotal.asCurrency),
                      AppSpacing.vGapSm,
                      _SummaryRow(
                          'Delivery Fee',
                          summary.deliveryCharges == 0
                              ? 'FREE'
                              : summary.deliveryCharges.asCurrency),
                      AppSpacing.vGapSm,
                      _SummaryRow('GST (18%)', summary.gstAmount.asCurrency),
                      if (state.couponDiscount > 0) ...[
                        AppSpacing.vGapSm,
                        _SummaryRow('Coupon Discount',
                            '- ${state.couponDiscount.asCurrency}'),
                      ],
                      const Divider(height: AppSpacing.xl),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Grand Total', style: AppTypography.titleLarge),
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
          _CheckoutBar(
            total: total,
            placing: state.placing,
            enabled: canPlace,
            label: state.paymentMethod == PaymentMethod.credit
                ? 'Pay on Credit'
                : 'Place Order',
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
              child: Text('“$applied” applied — ${discount.asCurrency} off',
                  style: AppTypography.labelMedium.copyWith(color: vs.success)),
            ),
            GestureDetector(
              onTap: onRemove,
              child: Text('Remove',
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
              decoration: const InputDecoration(
                hintText: 'Apply coupon (try VS100)',
                border: InputBorder.none,
              ),
            ),
          ),
          TextButton(onPressed: onApply, child: const Text('Apply')),
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
              child: _seg(context, 'Pay Now', !payOnCredit, onPayNow)),
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
        Text('Choose a repayment plan', style: AppTypography.labelLarge),
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
            Text('Due $date',
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
                Text('Payout date',
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
          child: Text('By placing this order, you agree to our Terms & Conditions and Return Policy.',
              style: AppTypography.bodySmall.copyWith(color: vs.textSecondary)),
        ),
      ],
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
                Text('Total',
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
