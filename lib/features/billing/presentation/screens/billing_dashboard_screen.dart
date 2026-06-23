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
import '../../../../shared/providers/core_providers.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/providers/current_user_provider.dart';
import '../../domain/entities/credit_ledger_entry.dart';
import '../providers/billing_providers.dart';
import '../widgets/transaction_tile.dart';

/// Credit Dashboard (Phase 4D) — the ledger-derived home of the credit system.
/// Every figure (available, used, current bill, minimum due, utilization, recent
/// activity) is computed by [billingOverviewProvider] off the credit ledger.
class BillingDashboardScreen extends ConsumerStatefulWidget {
  const BillingDashboardScreen({super.key});

  @override
  ConsumerState<BillingDashboardScreen> createState() =>
      _BillingDashboardScreenState();
}

class _BillingDashboardScreenState
    extends ConsumerState<BillingDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(analyticsServiceProvider).track('credit_dashboard_viewed');
    });
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final user = ref.watch(currentUserProvider);
    // KYC/credit is optional — until the customer is credit-verified, the Credit
    // tab shows an Apply-for-Credit (or pending / rejected) state instead of a
    // dashboard for an account they don't have yet.
    final creditActive = user?.isKycVerified ?? false;
    final overviewAsync = ref.watch(billingOverviewProvider);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('Credit',
            style: AppTypography.headlineSmall.copyWith(color: vs.brand)),
        actions: [
          if (creditActive)
            IconButton(
              icon: const Icon(Icons.receipt_long_rounded),
              tooltip: 'Statements',
              onPressed: () => context.pushNamed(RouteNames.statements),
            ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: creditActive
          ? RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(creditLedgerProvider);
                await ref.read(billingOverviewProvider.future);
              },
              child: overviewAsync.when(
                loading: () => const VSLoadingView(),
                error: (e, _) => VSErrorView(
                  failure: e is Failure ? e : null,
                  onRetry: () => ref.invalidate(billingOverviewProvider),
                ),
                data: (data) => _Body(data: data),
              ),
            )
          : _CreditLockedView(
              status: user?.kycStatus ?? KycStatus.notStarted,
            ),
    );
  }
}

/// Shown on the Credit tab when the customer hasn't unlocked VS Credit yet.
/// Drives the apply / under-review / rejected states off the KYC status.
class _CreditLockedView extends StatelessWidget {
  const _CreditLockedView({required this.status});

  final KycStatus status;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final (IconData icon, String title, String body, String cta, String route) =
        switch (status) {
      KycStatus.pending => (
          Icons.hourglass_top_rounded,
          'Application Under Review',
          "We're verifying your details. Your VS Credit line will unlock here "
              'once approved — usually within a few hours.',
          'View Status',
          RouteNames.verificationStatus,
        ),
      KycStatus.rejected => (
          Icons.error_outline_rounded,
          'Application Not Approved',
          "Your last credit application wasn't approved. You can review your "
              'details and apply again.',
          'Re-apply',
          RouteNames.kyc,
        ),
      _ => (
          Icons.credit_card_rounded,
          'Unlock VS Credit',
          'Shop now and pay later with a VS Credit line. Complete a quick KYC '
              'verification to apply — it only takes a few minutes.',
          'Apply for Credit',
          RouteNames.kyc,
        ),
    };

    return ListView(
      padding: AppSpacing.screen,
      children: [
        AppSpacing.vGapLg,
        Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: const BoxDecoration(
            gradient: AppColors.creditGradient,
            borderRadius: AppRadius.brXl,
          ),
          child: Column(
            children: [
              Container(
                height: 72,
                width: 72,
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.white, size: 36),
              ),
              AppSpacing.vGapLg,
              Text(title,
                  textAlign: TextAlign.center,
                  style: AppTypography.headlineSmall
                      .copyWith(color: AppColors.white)),
              AppSpacing.vGapSm,
              Text(body,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.white.withValues(alpha: 0.9))),
            ],
          ),
        ),
        AppSpacing.vGapLg,
        const _CreditBenefits(),
        AppSpacing.vGapXl,
        VSButton(
          label: cta,
          trailingIcon: Icons.arrow_forward_rounded,
          onPressed: () => context.pushNamed(route),
        ),
        AppSpacing.vGapMd,
        Row(
          children: [
            Icon(Icons.lock_outline_rounded, size: 16, color: vs.textSecondary),
            AppSpacing.hGapSm,
            Expanded(
              child: Text(
                'Your information is encrypted and used only for credit '
                'verification.',
                style: AppTypography.bodySmall
                    .copyWith(color: vs.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CreditBenefits extends StatelessWidget {
  const _CreditBenefits();

  static const _items = [
    (Icons.shopping_bag_outlined, 'Shop Now, Pay Later'),
    (Icons.calendar_month_rounded, 'Flexible Weekly / Monthly Plans'),
    (Icons.percent_rounded, 'Exclusive Member Offers'),
    (Icons.speed_rounded, 'Build Your VS Score'),
  ];

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
          Text('Why VS Credit?', style: AppTypography.titleLarge),
          AppSpacing.vGapMd,
          for (final (icon, label) in _items) ...[
            Row(
              children: [
                Icon(icon, size: 20, color: vs.brand),
                AppSpacing.hGapMd,
                Expanded(child: Text(label, style: AppTypography.bodyLarge)),
                Icon(Icons.check_circle_rounded, size: 18, color: vs.success),
              ],
            ),
            AppSpacing.vGapMd,
          ],
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.data});

  final BillingOverview data;

  @override
  Widget build(BuildContext context) {
    final due = data.nextDueDate;
    final statement = data.currentStatement;
    final hasDues = statement != null && !statement.paid;

    void viewStatement() {
      if (statement != null) {
        context.pushNamed(
          RouteNames.statementDetail,
          pathParameters: {'id': statement.statementId},
        );
      } else {
        context.pushNamed(RouteNames.statements);
      }
    }

    return ListView(
      padding: AppSpacing.screen,
      children: [
        _CreditHeroCard(
          available: data.available,
          used: data.outstanding,
          limit: data.creditLimit,
          utilization: data.utilization,
        ),
        AppSpacing.vGapMd,
        Row(
          children: [
            Expanded(
              child: VSButton(
                label: 'Make Payment',
                icon: Icons.payments_rounded,
                size: VSButtonSize.medium,
                onPressed: hasDues
                    ? () => context.pushNamed(RouteNames.repayment)
                    : null,
              ),
            ),
            AppSpacing.hGapMd,
            Expanded(
              child: VSOutlinedButton(
                label: 'View Statement',
                icon: Icons.description_outlined,
                onPressed: viewStatement,
              ),
            ),
          ],
        ),
        AppSpacing.vGapLg,
        if (hasDues)
          _CurrentBillCard(
            amountDue: statement.amountDue,
            minimumDue: data.minimumDue,
            dueDate: due == null ? '—' : DateFormat('d MMM yyyy').format(due),
            isOverdue: statement.isOverdue,
            onPay: () => context.pushNamed(RouteNames.repayment),
          )
        else
          _NoDuesCard(),
        AppSpacing.vGapLg,
        _RecentActivity(transactions: data.recentTransactions),
        AppSpacing.vGapLg,
        _NavGrid(),
      ],
    );
  }
}

class _CreditHeroCard extends StatelessWidget {
  const _CreditHeroCard({
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
                child: Text('${(utilization * 100).round()}% used',
                    style: AppTypography.labelSmall
                        .copyWith(color: AppColors.white)),
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
              value: utilization,
              minHeight: 8,
              backgroundColor: AppColors.white.withValues(alpha: 0.25),
              valueColor: AlwaysStoppedAnimation(
                utilization > 0.8 ? AppColors.warning : AppColors.success,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CurrentBillCard extends StatelessWidget {
  const _CurrentBillCard({
    required this.amountDue,
    required this.minimumDue,
    required this.dueDate,
    required this.isOverdue,
    required this.onPay,
  });

  final num amountDue;
  final num minimumDue;
  final String dueDate;
  final bool isOverdue;
  final VoidCallback onPay;

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
              Text('Current Bill', style: AppTypography.titleLarge),
              VSStatusChip(
                label: isOverdue ? 'Overdue' : 'Due $dueDate',
                tone: isOverdue ? VSStatusTone.danger : VSStatusTone.warning,
                icon: isOverdue
                    ? Icons.warning_amber_rounded
                    : Icons.schedule_rounded,
                dense: true,
              ),
            ],
          ),
          AppSpacing.vGapMd,
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total Amount Due',
                      style: AppTypography.bodySmall
                          .copyWith(color: vs.textSecondary)),
                  Text(amountDue.asCurrency,
                      style: AppTypography.priceLarge.copyWith(color: vs.danger)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Minimum Due',
                      style: AppTypography.bodySmall
                          .copyWith(color: vs.textSecondary)),
                  Text(minimumDue.asCurrency, style: AppTypography.labelLarge),
                ],
              ),
            ],
          ),
          AppSpacing.vGapMd,
          VSButton(
            label: 'Pay Now',
            icon: Icons.payments_rounded,
            onPressed: onPay,
          ),
        ],
      ),
    );
  }
}

class _NoDuesCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: vs.successTint,
        borderRadius: AppRadius.brLg,
      ),
      child: Row(
        children: [
          Icon(Icons.verified_rounded, color: vs.success, size: 28),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('All Caught Up', style: AppTypography.titleMedium),
                Text('You have no pending dues right now.',
                    style: AppTypography.bodySmall
                        .copyWith(color: vs.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            _ActionButton(
              icon: Icons.description_outlined,
              label: 'Statements',
              onTap: () => context.pushNamed(RouteNames.statements),
            ),
            AppSpacing.hGapMd,
            _ActionButton(
              icon: Icons.receipt_outlined,
              label: 'Invoices',
              onTap: () => context.pushNamed(RouteNames.invoices),
            ),
          ],
        ),
        AppSpacing.vGapMd,
        Row(
          children: [
            _ActionButton(
              icon: Icons.history_rounded,
              label: 'Payment History',
              onTap: () => context.pushNamed(RouteNames.paymentHistory),
            ),
            AppSpacing.hGapMd,
            _ActionButton(
              icon: Icons.local_atm_outlined,
              label: 'Collections',
              onTap: () => context.pushNamed(RouteNames.collections),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.brLg,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: AppRadius.brLg,
            border: Border.all(color: vs.border),
          ),
          child: Column(
            children: [
              Icon(icon, color: vs.trust, size: 26),
              AppSpacing.vGapSm,
              Text(label, style: AppTypography.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentActivity extends StatelessWidget {
  const _RecentActivity({required this.transactions});

  final List<CreditLedgerEntry> transactions;

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
          Text('Recent Activity', style: AppTypography.titleLarge),
          AppSpacing.vGapSm,
          if (transactions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text('No transactions yet.',
                  style: AppTypography.bodyMedium
                      .copyWith(color: vs.textSecondary)),
            )
          else
            for (var i = 0; i < transactions.length; i++)
              TransactionTile(
                entry: transactions[i],
                showDivider: i != transactions.length - 1,
              ),
        ],
      ),
    );
  }
}
