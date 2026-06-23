import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../credit/domain/credit_access.dart';
import '../../../credit/presentation/providers/credit_access_provider.dart';
import '../providers/billing_providers.dart';

/// Home payment-reminder banner (Phase 4K). Ledger-derived: it renders only when
/// there is an unpaid current statement, and collapses to nothing otherwise so
/// it can be dropped into any scroll view unconditionally.
class CreditDueBanner extends ConsumerWidget {
  const CreditDueBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // No-leak: only customers with active VS Credit ever see a due banner.
    if (ref.watch(creditAccessProvider).isLocked) return const SizedBox.shrink();
    final statement = ref.watch(currentStatementProvider).valueOrNull;
    if (statement == null || statement.paid) return const SizedBox.shrink();

    final vs = context.vsColors;
    final overdue = statement.isOverdue;
    final due = DateFormat('d MMM').format(statement.dueDate);
    final tint = overdue ? vs.dangerTint : vs.offerTint;
    final accent = overdue ? vs.danger : vs.offer;

    return Padding(
      padding: AppSpacing.screenHorizontal,
      child: InkWell(
        onTap: () => context.pushNamed(RouteNames.repayment),
        borderRadius: AppRadius.brLg,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: tint,
            borderRadius: AppRadius.brLg,
            border: Border.all(color: accent.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(
                overdue
                    ? Icons.warning_amber_rounded
                    : Icons.event_available_rounded,
                color: accent,
                size: 22,
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      overdue ? 'Payment overdue' : 'Payment due $due',
                      style: AppTypography.labelLarge.copyWith(color: accent),
                    ),
                    Text(
                      '${statement.amountDue.asCurrency} due • '
                      'min ${statement.minimumDue.asCurrency}',
                      style: AppTypography.bodySmall
                          .copyWith(color: vs.textSecondary),
                    ),
                  ],
                ),
              ),
              AppSpacing.hGapSm,
              Text('Pay',
                  style: AppTypography.labelLarge.copyWith(color: accent)),
              Icon(Icons.chevron_right_rounded, color: accent, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
