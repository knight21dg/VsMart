import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/order_enums.dart';
import '../../domain/entities/order_parts.dart';

/// Maps an [OrderStatus] to a status-chip tone.
VSStatusTone orderStatusTone(OrderStatus status) => switch (status) {
      OrderStatus.draft => VSStatusTone.warning,
      OrderStatus.pending => VSStatusTone.warning,
      OrderStatus.placed => VSStatusTone.warning,
      OrderStatus.confirmed => VSStatusTone.info,
      OrderStatus.packed => VSStatusTone.info,
      OrderStatus.readyForDispatch => VSStatusTone.info,
      OrderStatus.outForDelivery => VSStatusTone.brand,
      OrderStatus.delivered => VSStatusTone.success,
      OrderStatus.partiallyReturned => VSStatusTone.success,
      OrderStatus.cancelled => VSStatusTone.danger,
      OrderStatus.rejected => VSStatusTone.danger,
      OrderStatus.returned => VSStatusTone.danger,
      OrderStatus.failedDelivery => VSStatusTone.danger,
    };

/// Status pill for an order.
class VSOrderStatusChip extends StatelessWidget {
  const VSOrderStatusChip({super.key, required this.status, this.dense = false});

  final OrderStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return VSStatusChip(
      label: status.label,
      tone: orderStatusTone(status),
      dense: dense,
    );
  }
}

/// Vertical order progress timeline.
class VSOrderTimeline extends StatelessWidget {
  const VSOrderTimeline({super.key, required this.entries});

  final List<OrderTimelineEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < entries.length; i++)
          _Row(entry: entries[i], isLast: i == entries.length - 1),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.entry, required this.isLast});

  final OrderTimelineEntry entry;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final done = entry.done;
    final color = done ? vs.brand : vs.textSecondary;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                height: 22,
                width: 22,
                decoration: BoxDecoration(
                  color: done ? vs.brand : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                ),
                child: done
                    ? const Icon(Icons.check_rounded,
                        size: 13, color: AppColors.white)
                    : null,
              ),
              if (!isLast)
                Expanded(child: Container(width: 2, color: vs.border)),
            ],
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.label,
                      style: AppTypography.titleMedium.copyWith(
                        color: done ? null : vs.textSecondary,
                      )),
                  if (entry.at != null)
                    Text(DateFormat('d MMM, h:mm a').format(entry.at!),
                        style: AppTypography.bodySmall
                            .copyWith(color: vs.textSecondary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bill breakdown for an order.
class VSOrderSummary extends StatelessWidget {
  const VSOrderSummary({super.key, required this.summary});

  final OrderSummary summary;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    Widget row(String label, String value, {Color? color, bool bold = false}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: AppTypography.bodyMedium
                      .copyWith(color: vs.textSecondary)),
              Text(value,
                  style: bold
                      ? AppTypography.priceMedium
                      : AppTypography.labelLarge.copyWith(color: color)),
            ],
          ),
        );
    return Column(
      children: [
        row('Item Total', summary.itemTotal.asCurrency),
        row(
            'Delivery Fee',
            summary.deliveryFee == 0
                ? 'FREE'
                : summary.deliveryFee.asCurrency,
            color: summary.deliveryFee == 0 ? vs.success : null),
        if (summary.discount > 0)
          row('Discount', '- ${summary.discount.asCurrency}',
              color: vs.success),
        const Divider(height: AppSpacing.lg),
        row('Grand Total', summary.grandTotal.asCurrency, bold: true),
      ],
    );
  }
}
