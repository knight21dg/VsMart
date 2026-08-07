import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../extensions/context_extensions.dart';
import '../extensions/num_extensions.dart';
import 'vs_network_image.dart';
import 'vs_status_chip.dart';

/// Summary card for an order in the orders list.
class VSOrderCard extends StatelessWidget {
  const VSOrderCard({
    super.key,
    required this.orderId,
    required this.statusLabel,
    required this.statusTone,
    required this.total,
    required this.itemCount,
    required this.dateLabel,
    this.thumbnailUrls = const [],
    this.onTap,
    this.onTrack,
    this.onReorder,
  });

  final String orderId;
  final String statusLabel;
  final VSStatusTone statusTone;
  final num total;
  final int itemCount;
  final String dateLabel;
  final List<String> thumbnailUrls;
  final VoidCallback? onTap;
  final VoidCallback? onTrack;
  final VoidCallback? onReorder;

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
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Order #$orderId',
                          style: AppTypography.titleMedium),
                      const SizedBox(height: 2),
                      Text(dateLabel,
                          style: AppTypography.bodySmall
                              .copyWith(color: vs.textSecondary)),
                    ],
                  ),
                ),
                VSStatusChip(label: statusLabel, tone: statusTone),
              ],
            ),
            const Divider(height: AppSpacing.xl),
            Row(
              children: [
                ...thumbnailUrls.take(3).map(
                      (u) => Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: VSNetworkImage(
                          url: u,
                          width: 40,
                          height: 40,
                          borderRadius: AppRadius.brSm,
                        ),
                      ),
                    ),
                Expanded(
                  child: Text(
                    '$itemCount item${itemCount == 1 ? '' : 's'}',
                    style: AppTypography.bodySmall
                        .copyWith(color: vs.textSecondary),
                  ),
                ),
                Text(total.asCurrency, style: AppTypography.priceMedium),
              ],
            ),
            if (onTrack != null || onReorder != null) ...[
              AppSpacing.vGapMd,
              Row(
                children: [
                  if (onTrack != null)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onTrack,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          shape: const RoundedRectangleBorder(
                              borderRadius: AppRadius.brSm),
                        ),
                        child: const Text('Track'),
                      ),
                    ),
                  if (onTrack != null && onReorder != null)
                    AppSpacing.hGapMd,
                  if (onReorder != null)
                    Expanded(
                      child: FilledButton(
                        onPressed: onReorder,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          shape: const RoundedRectangleBorder(
                              borderRadius: AppRadius.brSm),
                        ),
                        child: const Text('Reorder'),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
