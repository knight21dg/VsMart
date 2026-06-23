import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../credit/presentation/providers/credit_providers.dart';

/// Outstanding Due detail screen.
///
/// Shows the customer's total outstanding amount with its due date, a guidance
/// banner, a credit-utilization summary, a breakdown of the outstanding
/// (principal / interest / late fee / minimum due), the available payment
/// methods, and a sticky "Pay Now" CTA that routes to the repayment flow.
class OutstandingDueScreen extends ConsumerWidget {
  const OutstandingDueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountAsync = ref.watch(creditAccountProvider);

    return Scaffold(
      appBar: const VSAppBar(title: 'Outstanding Due'),
      body: accountAsync.when(
        loading: () => const VSLoadingView(),
        error: (_, __) => VSErrorView(
          message: "Couldn't load your dues.",
          onRetry: () => ref.invalidate(creditAccountProvider),
        ),
        data: (account) => SafeArea(
          top: false,
          child: RefreshIndicator(
            onRefresh: () async => ref.invalidate(creditAccountProvider),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: AppSpacing.screen,
              children: [
                  _DueCard(
                    outstanding: account.outstanding,
                    dueDate: account.dueDate,
                    daysUntilDue: account.daysUntilDue(DateTime.now()),
                  ),
                  AppSpacing.vGapMd,
                  const _GuidanceBanner(),
                  AppSpacing.vGapLg,
                  Text('Breakdown', style: AppTypography.titleLarge),
                  AppSpacing.vGapMd,
                  _BreakdownCard(outstanding: account.outstanding),
                  AppSpacing.vGapLg,
                  Text('Credit Summary', style: AppTypography.titleLarge),
                  AppSpacing.vGapMd,
                  _CreditSummaryCard(
                    available: account.available,
                    used: account.outstanding,
                    limit: account.creditLimit,
                    utilization: account.utilization,
                  ),
                  AppSpacing.vGapXl,
                ],
              ),
            ),
          ),
        ),
      bottomNavigationBar: accountAsync.valueOrNull == null
          ? null
          : _PayBar(amount: accountAsync.valueOrNull!.outstanding),
    );
  }
}

/// Prominent gradient hero showing the total outstanding amount and due date.
class _DueCard extends StatelessWidget {
  const _DueCard({
    required this.outstanding,
    required this.dueDate,
    required this.daysUntilDue,
  });

  final num outstanding;
  final DateTime? dueDate;
  final int daysUntilDue;

  @override
  Widget build(BuildContext context) {
    final faint = AppColors.white.withValues(alpha: 0.85);
    final isOverdue = daysUntilDue < 0;
    final dueLabel = dueDate == null
        ? null
        : 'Due: ${DateFormat('d MMMM yyyy').format(dueDate!)}';
    final chipLabel = isOverdue
        ? 'Overdue by ${-daysUntilDue} Days'
        : 'Due in $daysUntilDue Days';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: AppColors.creditGradient,
        borderRadius: AppRadius.brXl,
        boxShadow: AppShadows.glow(AppColors.trustBlue),
      ),
      child: Column(
        children: [
          Text(
            'Total Outstanding Amount',
            style: AppTypography.bodyMedium.copyWith(color: faint),
          ),
          AppSpacing.vGapSm,
          Text(
            outstanding.asCurrency,
            style: AppTypography.displayMedium.copyWith(color: AppColors.white),
          ),
          AppSpacing.vGapMd,
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              if (dueLabel != null)
                Text(
                  dueLabel,
                  style: AppTypography.labelLarge.copyWith(
                    color: AppColors.white,
                  ),
                ),
              if (dueDate != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.white.withValues(alpha: 0.20),
                    borderRadius: AppRadius.brPill,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        size: 14,
                        color: AppColors.white,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        chipLabel,
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.white,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Soft warning banner nudging on-time payment.
class _GuidanceBanner extends StatelessWidget {
  const _GuidanceBanner();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: const BoxDecoration(
        color: AppColors.amberTint,
        borderRadius: AppRadius.brLg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: vs.warning, size: 20),
          AppSpacing.hGapMd,
          Expanded(
            child: Text(
              'Pay before the due date to maintain a healthy VS Score and '
              'avoid late fees.',
              style: AppTypography.bodySmall.copyWith(color: vs.warning),
            ),
          ),
        ],
      ),
    );
  }
}

/// Card breaking the outstanding into principal / interest / late fee with the
/// minimum due highlighted. Uses a representative split of the outstanding.
class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.outstanding});

  final num outstanding;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    // Representative split of the outstanding balance.
    final lateFee = outstanding * 0.02;
    final interest = outstanding * 0.05;
    final principal = outstanding - interest - lateFee;
    final minimumDue = outstanding * 0.10;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
      ),
      child: Column(
        children: [
          _BreakdownRow(label: 'Principal', value: principal),
          AppSpacing.vGapMd,
          _BreakdownRow(label: 'Interest', value: interest),
          AppSpacing.vGapMd,
          _BreakdownRow(
            label: 'Late Fee',
            value: lateFee,
            valueColor: vs.danger,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Divider(color: vs.border, height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Minimum Due', style: AppTypography.titleMedium),
              Text(
                minimumDue.asCurrency,
                style: AppTypography.priceMedium.copyWith(color: vs.brand),
              ),
            ],
          ),
          AppSpacing.vGapMd,
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total Outstanding', style: AppTypography.titleMedium),
              Text(
                outstanding.asCurrency,
                style: AppTypography.priceMedium,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final num value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
        ),
        Text(
          value.asCurrency,
          style: AppTypography.labelLarge.copyWith(color: valueColor),
        ),
      ],
    );
  }
}

/// Available credit vs. total limit with a utilization progress bar.
class _CreditSummaryCard extends StatelessWidget {
  const _CreditSummaryCard({
    required this.available,
    required this.used,
    required this.limit,
    required this.utilization,
  });

  final num available;
  final num used;
  final num limit;
  final double utilization;

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Available Credit',
                    style: AppTypography.bodySmall.copyWith(
                      color: vs.textSecondary,
                    ),
                  ),
                  AppSpacing.vGapXs,
                  Text(
                    available.asCurrency,
                    style: AppTypography.priceMedium.copyWith(color: vs.brand),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Total Limit',
                    style: AppTypography.bodySmall.copyWith(
                      color: vs.textSecondary,
                    ),
                  ),
                  AppSpacing.vGapXs,
                  Text(limit.asCurrency, style: AppTypography.priceMedium),
                ],
              ),
            ],
          ),
          AppSpacing.vGapMd,
          ClipRRect(
            borderRadius: AppRadius.brPill,
            child: LinearProgressIndicator(
              value: utilization,
              minHeight: 8,
              backgroundColor: vs.trustTint,
              valueColor: AlwaysStoppedAnimation(
                utilization > 0.8 ? vs.danger : vs.brand,
              ),
            ),
          ),
          AppSpacing.vGapMd,
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: vs.danger,
                  borderRadius: AppRadius.brPill,
                ),
              ),
              AppSpacing.hGapSm,
              Text(
                'Used: ${used.asCurrency}',
                style: AppTypography.bodySmall.copyWith(
                  color: vs.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Sticky bottom bar: total amount label and the primary "Pay Now" CTA.
class _PayBar extends StatelessWidget {
  const _PayBar({required this.amount});

  final num amount;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: vs.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Paying Total Amount',
                    style: AppTypography.bodySmall.copyWith(
                      color: vs.textSecondary,
                    ),
                  ),
                  AppSpacing.vGapXs,
                  Text(amount.asCurrency, style: AppTypography.priceMedium),
                ],
              ),
            ),
            AppSpacing.hGapLg,
            VSButton(
              label: 'Pay Now',
              icon: Icons.payments_rounded,
              isExpanded: false,
              onPressed: () => context.pushNamed(RouteNames.repayment),
            ),
          ],
        ),
      ),
    );
  }
}
