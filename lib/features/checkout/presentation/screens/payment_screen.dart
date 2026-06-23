import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/app_error_presenter.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../credit/presentation/providers/credit_providers.dart';
import '../../../orders/domain/entities/order_enums.dart';
import '../providers/checkout_controller.dart';

/// Payment Method selection — matches the design: amount card, "Select Option"
/// radio list (green-check selected state), secure note and a Continue CTA.
/// Places the order via [checkoutControllerProvider] on confirm.
class PaymentScreen extends ConsumerWidget {
  const PaymentScreen({super.key});

  // Display order matching the design's single-select list.
  static const _methods = [
    PaymentMethod.upi,
    PaymentMethod.card,
    PaymentMethod.cashOnDelivery,
    PaymentMethod.credit,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(checkoutControllerProvider.notifier);
    final state = ref.watch(checkoutControllerProvider);
    final total = controller.grandTotal();
    final creditAvailable =
        ref.watch(creditAccountProvider).valueOrNull?.available;

    Future<void> proceed() async {
      final order = await controller.placeOrder();
      if (!context.mounted) return;
      if (order == null) {
        final err = ref.read(checkoutControllerProvider).error;
        // Actionable backend errors (KYC_REQUIRED, zone gates, credit limits…)
        // drive navigation/dialogs; bare failures fall back to a snackbar.
        if (err != null && err.isActionable) {
          presentFailure(context, ref, err, onRetry: proceed);
        } else {
          context.showSnack(
            err?.message ??
                'Could not complete payment. Check your cart and address.',
            isError: true,
          );
        }
        return;
      }
      // Settle online (UPI/card) payment via Razorpay. COD/credit need none.
      final paid = await controller.settleOrderPayment(order);
      if (!context.mounted) return;
      if (!paid) {
        context.showSnack(
          'Payment not completed. Your order is saved — you can retry from My Orders.',
          isError: true,
        );
      }
      context.goNamed(RouteNames.orderSuccess);
    }

    return Scaffold(
      appBar: const VSAppBar(title: 'Payment Method'),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: AppSpacing.screen,
                children: [
                  _AmountCard(total: total),
                  AppSpacing.vGapLg,
                  Text('Select Option', style: AppTypography.titleLarge),
                  AppSpacing.vGapMd,
                  for (final m in _methods) ...[
                    _MethodTile(
                      method: m,
                      selected: state.paymentMethod == m,
                      creditAvailable: creditAvailable,
                      onTap: () => controller.selectPaymentMethod(m),
                    ),
                    AppSpacing.vGapMd,
                  ],
                  AppSpacing.vGapSm,
                  _SecureNote(),
                ],
              ),
            ),
            Container(
              padding: AppSpacing.screen,
              decoration: BoxDecoration(
                color: context.colors.surface,
                border: Border(top: BorderSide(color: context.vsColors.border)),
              ),
              child: VSButton(
                label: 'Continue',
                isLoading: state.placing,
                onPressed: proceed,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountCard extends StatelessWidget {
  const _AmountCard({required this.total});

  final num total;

  static const _gradient = LinearGradient(
    colors: [AppColors.trustBlue, Color(0xFF1D4ED8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  @override
  Widget build(BuildContext context) {
    final faint = AppColors.white.withValues(alpha: 0.85);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: const BoxDecoration(
        gradient: _gradient,
        borderRadius: AppRadius.brLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Amount Payable',
              style: AppTypography.bodyMedium.copyWith(color: faint)),
          AppSpacing.vGapXs,
          Text(total.asCurrency,
              style:
                  AppTypography.displayMedium.copyWith(color: AppColors.white)),
          AppSpacing.vGapSm,
          Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 14, color: faint),
              const SizedBox(width: 4),
              Text('Inclusive of all charges',
                  style: AppTypography.bodySmall.copyWith(color: faint)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.method,
    required this.selected,
    required this.onTap,
    this.creditAvailable,
  });

  final PaymentMethod method;
  final bool selected;
  final VoidCallback onTap;
  final num? creditAvailable;

  ({IconData icon, String subtitle, Color color}) _meta(BuildContext context) {
    final vs = context.vsColors;
    return switch (method) {
      PaymentMethod.upi => (
          icon: Icons.account_balance_rounded,
          subtitle: 'Instant Payment',
          color: vs.brand,
        ),
      PaymentMethod.card => (
          icon: Icons.credit_card_rounded,
          subtitle: 'Credit / Debit card',
          color: vs.trust,
        ),
      PaymentMethod.cashOnDelivery => (
          icon: Icons.payments_outlined,
          subtitle: 'Pay on delivery',
          color: vs.offer,
        ),
      PaymentMethod.credit => (
          icon: Icons.account_balance_wallet_rounded,
          subtitle: creditAvailable != null
              ? 'Buy now, pay later · ${creditAvailable!.asCurrency} available'
              : 'Buy now, pay later',
          color: vs.trust,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final meta = _meta(context);
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brLg,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: selected ? vs.brandTint.withValues(alpha: 0.4)
              : context.colors.surface,
          borderRadius: AppRadius.brLg,
          border: Border.all(
            color: selected ? vs.brand : vs.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: meta.color.withValues(alpha: 0.12),
                borderRadius: AppRadius.brMd,
              ),
              child: Icon(meta.icon, color: meta.color, size: 20),
            ),
            AppSpacing.hGapMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(method.label, style: AppTypography.titleMedium),
                  const SizedBox(height: 2),
                  Text(meta.subtitle,
                      style: AppTypography.bodySmall
                          .copyWith(color: vs.textSecondary)),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, color: vs.brand)
            else
              Icon(Icons.radio_button_unchecked_rounded,
                  color: vs.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _SecureNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: vs.trustTint.withValues(alpha: 0.5),
        borderRadius: AppRadius.brMd,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline_rounded, size: 16, color: vs.textSecondary),
          AppSpacing.hGapSm,
          Text('Payments secured by Razorpay.',
              style:
                  AppTypography.bodySmall.copyWith(color: vs.textSecondary)),
        ],
      ),
    );
  }
}
