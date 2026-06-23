import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/credit_account.dart';
import '../providers/credit_providers.dart';

/// Credit tab dashboard: available credit, next payment due, quick actions, and
/// the current month's credit activity. Backed by [creditAccountProvider].
class CreditDashboardScreen extends ConsumerWidget {
  const CreditDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    final accountAsync = ref.watch(creditAccountProvider);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('Credit Dashboard',
            style: AppTypography.headlineSmall.copyWith(color: vs.brand)),
        actions: [
          IconButton(
            icon: const Badge(
              smallSize: 8,
              child: Icon(Icons.notifications_none_rounded),
            ),
            onPressed: () => context.pushNamed(RouteNames.notifications),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: accountAsync.when(
        loading: () => const VSLoadingView(),
        error: (e, _) => VSErrorView(
          failure: e is Failure ? e : null,
          onRetry: () => ref.invalidate(creditAccountProvider),
        ),
        data: (account) => _DashboardBody(account: account),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.account});

  final CreditAccount account;

  @override
  Widget build(BuildContext context) {
    final due = account.dueDate;
    final daysLeft = account.daysUntilDue(DateTime.now());
    final cycle = account.billingCycle == BillingCycle.weekly
        ? 'Weekly Cycle'
        : 'Monthly Cycle';
    return ListView(
      padding: AppSpacing.screen,
      children: [
        if (!account.isActive) ...[
          _AccountStatusBanner(status: account.status),
          AppSpacing.vGapLg,
        ],
        _CreditHeroCard(
          available: account.available,
          used: account.outstanding,
          limit: account.creditLimit,
          vsScore: account.vsScore,
        ),
        AppSpacing.vGapLg,
        _NextPaymentCard(
          outstanding: account.outstanding,
          dueAmount: account.nextDueAmount,
          dueDate: due == null ? '—' : DateFormat('d MMMM yyyy').format(due),
          daysLeft: daysLeft,
          cycle: cycle,
        ),
        AppSpacing.vGapLg,
        _ActionsRow(
          onPay: () => context.pushNamed(RouteNames.makePayment),
          onStatement: () => context.pushNamed(RouteNames.monthlyBill),
          onHistory: () => context.pushNamed(RouteNames.paymentHistory),
        ),
        AppSpacing.vGapLg,
        _MonthlyActivityCard(
          purchases: account.purchasesThisMonth,
          paymentsMade: account.paymentsThisMonth,
          remaining: account.available,
        ),
        if (account.hasLendingPartner) ...[
          AppSpacing.vGapLg,
          _LenderDisclosure(account: account),
        ],
      ],
    );
  }
}

class _CreditHeroCard extends StatelessWidget {
  const _CreditHeroCard({
    required this.available,
    required this.used,
    required this.limit,
    required this.vsScore,
  });

  final num available;
  final num used;
  final num limit;
  final int vsScore;

  @override
  Widget build(BuildContext context) {
    final ratio = (used / limit).clamp(0.0, 1.0);
    final faint = AppColors.white.withValues(alpha: 0.85);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: AppColors.creditGradient,
        borderRadius: AppRadius.brXl,
        boxShadow: AppShadows.glow(AppColors.trustBlue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Available Credit',
                  style: AppTypography.bodyMedium.copyWith(color: faint)),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.18),
                  borderRadius: AppRadius.brPill,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified_rounded,
                        color: AppColors.white, size: 14),
                    const SizedBox(width: AppSpacing.xs),
                    Text('VS Score: $vsScore',
                        style: AppTypography.labelSmall
                            .copyWith(color: AppColors.white)),
                  ],
                ),
              ),
            ],
          ),
          AppSpacing.vGapXs,
          Text(available.asCurrency,
              style:
                  AppTypography.displayMedium.copyWith(color: AppColors.white)),
          AppSpacing.vGapLg,
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Used: ${used.asCurrency}',
                  style: AppTypography.bodySmall.copyWith(color: faint)),
              Text('Total Limit: ${limit.asCurrency}',
                  style: AppTypography.bodySmall.copyWith(color: faint)),
            ],
          ),
          AppSpacing.vGapSm,
          ClipRRect(
            borderRadius: AppRadius.brPill,
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: AppColors.white.withValues(alpha: 0.25),
              valueColor: const AlwaysStoppedAnimation(AppColors.success),
            ),
          ),
        ],
      ),
    );
  }
}

class _NextPaymentCard extends StatelessWidget {
  const _NextPaymentCard({
    required this.outstanding,
    required this.dueAmount,
    required this.dueDate,
    required this.daysLeft,
    required this.cycle,
  });

  final num outstanding;
  final num dueAmount;
  final String dueDate;
  final int daysLeft;
  final String cycle;

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
          Text('Next Payment Due', style: AppTypography.titleLarge),
          AppSpacing.vGapMd,
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Outstanding Amount',
                      style: AppTypography.bodySmall
                          .copyWith(color: vs.textSecondary)),
                  Text(outstanding.asCurrency,
                      style:
                          AppTypography.priceLarge.copyWith(color: vs.danger)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Due Date',
                      style: AppTypography.bodySmall
                          .copyWith(color: vs.textSecondary)),
                  Text(dueDate, style: AppTypography.labelLarge),
                ],
              ),
            ],
          ),
          AppSpacing.vGapMd,
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: vs.dangerTint,
              borderRadius: AppRadius.brSm,
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 16, color: vs.danger),
                AppSpacing.hGapSm,
                Expanded(
                  child: Text(
                    dueAmount > 0
                        ? '${dueAmount.asCurrency} due in $daysLeft Days • $cycle'
                        : 'Due in $daysLeft Days • $cycle',
                    style: AppTypography.labelMedium.copyWith(color: vs.danger),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Banner shown when the credit line is frozen or closed.
class _AccountStatusBanner extends StatelessWidget {
  const _AccountStatusBanner({required this.status});

  final CreditAccountStatus status;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final frozen = status == CreditAccountStatus.frozen;
    final message = frozen
        ? 'Your credit line is frozen. New credit purchases are paused until your outstanding is cleared.'
        : 'Your credit line is closed. Please contact support for assistance.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: vs.dangerTint,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(frozen ? Icons.ac_unit_rounded : Icons.lock_rounded,
              size: 20, color: vs.danger),
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

/// Regulatory disclosure of the NBFC/LSP lending partner backing the credit line.
class _LenderDisclosure extends StatelessWidget {
  const _LenderDisclosure({required this.account});

  final CreditAccount account;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final parts = <String>[
      if ((account.loanAccountNumber ?? '').isNotEmpty)
        'Loan A/c ${account.loanAccountNumber}',
      if (account.interestRate != null)
        '${account.interestRate}% p.a.',
      if (account.sanctionedLimit != null)
        'Sanctioned ${account.sanctionedLimit!.asCurrency}',
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
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
              Icon(Icons.verified_user_outlined, size: 16, color: vs.textSecondary),
              AppSpacing.hGapSm,
              Expanded(
                child: Text('Credit facility provided by ${account.lenderName}',
                    style: AppTypography.labelMedium),
              ),
            ],
          ),
          if (parts.isNotEmpty) ...[
            AppSpacing.vGapXs,
            Text(parts.join('  •  '),
                style: AppTypography.bodySmall.copyWith(color: vs.textSecondary)),
          ],
        ],
      ),
    );
  }
}

class _ActionsRow extends StatelessWidget {
  const _ActionsRow({
    required this.onPay,
    required this.onStatement,
    required this.onHistory,
  });

  final VoidCallback onPay;
  final VoidCallback onStatement;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          VSButton(
            label: 'Pay Outstanding',
            icon: Icons.payments_rounded,
            isExpanded: false,
            size: VSButtonSize.medium,
            onPressed: onPay,
          ),
          AppSpacing.hGapSm,
          VSOutlinedButton(
            label: 'View Statement',
            icon: Icons.description_outlined,
            isExpanded: false,
            onPressed: onStatement,
          ),
          AppSpacing.hGapSm,
          VSOutlinedButton(
            label: 'History',
            icon: Icons.history_rounded,
            isExpanded: false,
            onPressed: onHistory,
          ),
        ],
      ),
    );
  }
}

class _MonthlyActivityCard extends StatelessWidget {
  const _MonthlyActivityCard({
    required this.purchases,
    required this.paymentsMade,
    required this.remaining,
  });

  final num purchases;
  final num paymentsMade;
  final num remaining;

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
          Text("This Month's Activity", style: AppTypography.titleLarge),
          AppSpacing.vGapMd,
          _ActivityRow(
            icon: Icons.shopping_bag_outlined,
            tint: vs.offerTint,
            iconColor: vs.offer,
            label: 'Purchases',
            value: purchases.asCurrency,
          ),
          const Divider(height: AppSpacing.xl),
          _ActivityRow(
            icon: Icons.south_rounded,
            tint: vs.successTint,
            iconColor: vs.success,
            label: 'Payments Made',
            value: paymentsMade.asCurrency,
            valueColor: vs.success,
          ),
          const Divider(height: AppSpacing.xl),
          _ActivityRow(
            icon: Icons.credit_card_rounded,
            tint: vs.trustTint,
            iconColor: vs.trust,
            label: 'Remaining Credit',
            value: remaining.asCurrency,
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.icon,
    required this.tint,
    required this.iconColor,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final Color tint;
  final Color iconColor;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          height: 36,
          width: 36,
          decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        AppSpacing.hGapMd,
        Expanded(child: Text(label, style: AppTypography.bodyLarge)),
        Text(value,
            style: AppTypography.labelLarge.copyWith(color: valueColor)),
      ],
    );
  }
}
