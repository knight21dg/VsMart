import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../domain/entities/billing_enums.dart';
import '../../domain/entities/credit_ledger_entry.dart';

/// One ledger line rendered consistently across the dashboard and statement
/// detail: an icon tinted by direction, description + date, and a signed amount.
class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.entry, this.showDivider = true});

  final CreditLedgerEntry entry;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final isDebit = entry.type.isDebit;
    final (icon, tint, fg) = switch (entry.type) {
      TransactionType.purchase => (Icons.shopping_bag_outlined, vs.offerTint, vs.offer),
      TransactionType.penalty => (Icons.gpp_bad_outlined, vs.dangerTint, vs.danger),
      TransactionType.repayment => (Icons.south_rounded, vs.successTint, vs.success),
      TransactionType.refund => (Icons.replay_rounded, vs.trustTint, vs.trust),
      TransactionType.adjustment => (Icons.tune_rounded, vs.brandTint, vs.brand),
    };
    final amountColor = isDebit ? vs.danger : vs.success;
    final sign = isDebit ? '+' : '−';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              Container(
                height: 40,
                width: 40,
                decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                child: Icon(icon, size: 20, color: fg),
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyLarge),
                    AppSpacing.vGapXs,
                    Text(
                      '${entry.type.label} • ${DateFormat('d MMM yyyy').format(entry.date)}',
                      style: AppTypography.bodySmall
                          .copyWith(color: vs.textSecondary),
                    ),
                  ],
                ),
              ),
              AppSpacing.hGapSm,
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$sign${entry.amount.asCurrency}',
                      style:
                          AppTypography.labelLarge.copyWith(color: amountColor)),
                  if (entry.balanceAfter != null)
                    Text('Bal ${entry.balanceAfter!.asCurrency}',
                        style: AppTypography.bodySmall
                            .copyWith(color: vs.textSecondary)),
                ],
              ),
            ],
          ),
        ),
        if (showDivider) Divider(height: 1, color: vs.border),
      ],
    );
  }
}

/// Maps the billing statuses to a [VSStatusTone]-compatible tone string set used
/// by the screens. Kept here so list/detail render identical chips.
extension InvoiceStatusToneX on InvoiceStatus {
  IconData get icon => switch (this) {
        InvoiceStatus.paid => Icons.check_circle_rounded,
        InvoiceStatus.pending => Icons.schedule_rounded,
        InvoiceStatus.overdue => Icons.warning_amber_rounded,
        InvoiceStatus.cancelled => Icons.cancel_rounded,
      };
}
