import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
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
                  Text('Order Placed!',
                      textAlign: TextAlign.center,
                      style: AppTypography.headlineLarge),
                  AppSpacing.vGapSm,
                  Text('Thank you! Your order is confirmed and being prepared.',
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
                          _row(context, 'Order ID', order.id),
                          const Divider(height: AppSpacing.xl),
                          _row(context, 'Order Amount',
                              order.summary.grandTotal.asCurrency),
                          const Divider(height: AppSpacing.xl),
                          _row(context, 'Payment', order.payment.method.label),
                          if (order.payment.creditUsed > 0) ...[
                            const Divider(height: AppSpacing.xl),
                            _row(context, 'Credit Used',
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
                  if (order != null)
                    VSButton(
                      label: 'Track Order',
                      trailingIcon: Icons.local_shipping_outlined,
                      onPressed: () => context.pushReplacementNamed(
                        RouteNames.orderTracking,
                        pathParameters: {'orderId': order.id},
                      ),
                    ),
                  AppSpacing.vGapSm,
                  Row(
                    children: [
                      Expanded(
                        child: VSOutlinedButton(
                          label: 'View Orders',
                          onPressed: () => context.goNamed(RouteNames.orders),
                        ),
                      ),
                      AppSpacing.hGapMd,
                      Expanded(
                        child: VSOutlinedButton(
                          label: 'Continue Shopping',
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
