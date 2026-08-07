import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/l10n/status_labels.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../orders/domain/entities/order_enums.dart';
import '../providers/checkout_controller.dart';

/// Confirmation shown after an order is placed. Reads [lastPlacedOrderProvider].
class OrderSuccessScreen extends ConsumerWidget {
  const OrderSuccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    final order = ref.watch(lastPlacedOrderProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: AppSpacing.screen,
                children: [
                  const SizedBox(height: AppSpacing.xl),
                  Center(
                    child: Container(
                      height: 88,
                      width: 88,
                      decoration: const BoxDecoration(
                          color: AppColors.vsGreen, shape: BoxShape.circle),
                      child: const Icon(Icons.check_rounded,
                          color: AppColors.white, size: 48),
                    ),
                  ),
                  AppSpacing.vGapLg,
                  Text(context.l10n.checkoutOrderPlacedTitle,
                      textAlign: TextAlign.center,
                      style: AppTypography.headlineLarge),
                  AppSpacing.vGapSm,
                  Text(context.l10n.checkoutOrderConfirmedBody,
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium
                          .copyWith(color: vs.textSecondary)),
                  AppSpacing.vGapXl,
                  if (order != null)
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: context.colors.surface,
                        borderRadius: AppRadius.brLg,
                        border: Border.all(color: vs.border),
                      ),
                      child: Column(
                        children: [
                          _row(context, context.l10n.orderId, order.id),
                          const Divider(height: AppSpacing.xl),
                          _row(context, context.l10n.orderGrandTotal,
                              order.summary.grandTotal.asCurrency),
                          const Divider(height: AppSpacing.xl),
                          _row(context, 'Payment',
                              order.payment.method.labelL10n(context.l10n)),
                          if (order.payment.creditUsed > 0) ...[
                            const Divider(height: AppSpacing.xl),
                            _row(context, context.l10n.creditUsed,
                                order.payment.creditUsed.asCurrency),
                          ],
                          const Divider(height: AppSpacing.xl),
                          _row(
                            context,
                            'Estimated Delivery',
                            order.estimatedDelivery == null
                                ? '—'
                                : DateFormat('d MMM, h:mm a')
                                    .format(order.estimatedDelivery!),
                          ),
                          const Divider(height: AppSpacing.xl),
                          _row(context, 'Order Date',
                              DateFormat('d MMM yyyy').format(order.placedAt)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: AppSpacing.screen,
              child: Column(
                children: [
                  // A just-placed order is `pending` — there is nothing to
                  // track yet. Send the customer to the order instead; Track
                  // appears there once the store dispatches it.
                  if (order != null)
                    VSButton(
                      label: order.status.isTrackable
                          ? context.l10n.ordersTrack
                          : context.l10n.commonViewDetails,
                      trailingIcon: order.status.isTrackable
                          ? Icons.local_shipping_outlined
                          : Icons.receipt_long_outlined,
                      onPressed: () => context.pushReplacementNamed(
                        order.status.isTrackable
                            ? RouteNames.orderTracking
                            : RouteNames.orderDetails,
                        pathParameters: {'orderId': order.id},
                      ),
                    ),
                  AppSpacing.vGapSm,
                  Row(
                    children: [
                      Expanded(
                        child: VSOutlinedButton(
                          label: context.l10n.checkoutViewOrders,
                          onPressed: () => context.goNamed(RouteNames.orders),
                        ),
                      ),
                      AppSpacing.hGapMd,
                      Expanded(
                        child: VSOutlinedButton(
                          label: context.l10n.homeContinueShopping,
                          onPressed: () => context.goNamed(RouteNames.home),
                        ),
                      ),
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

  Widget _row(BuildContext context, String label, String value) {
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
