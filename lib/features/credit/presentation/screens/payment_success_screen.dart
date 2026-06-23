import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/credit_payment_result.dart';
import '../providers/credit_providers.dart';

/// Post-payment confirmation: receipt details, the refreshed credit standing,
/// and a VS-score reward callout. Reads [lastPaymentResultProvider].
class PaymentSuccessScreen extends ConsumerWidget {
  const PaymentSuccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    final result = ref.watch(lastPaymentResultProvider);

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
                        color: AppColors.vsGreen,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: AppColors.white, size: 48),
                    ),
                  ),
                  AppSpacing.vGapLg,
                  Text('Payment Successful',
                      textAlign: TextAlign.center,
                      style: AppTypography.headlineLarge),
                  AppSpacing.vGapSm,
                  Text('Your transaction was completed successfully.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium
                          .copyWith(color: vs.textSecondary)),
                  AppSpacing.vGapXl,
                  _DetailsCard(result: result),
                  if (result != null) ...[
                    AppSpacing.vGapLg,
                    _FinancialStatusCard(result: result),
                    AppSpacing.vGapLg,
                    _ScoreRewardCard(points: result.scorePointsEarned),
                  ],
                ],
              ),
            ),
            Padding(
              padding: AppSpacing.screen,
              child: Column(
                children: [
                  VSButton(
                    label: 'Back To Dashboard',
                    onPressed: () =>
                        context.goNamed(RouteNames.creditDashboard),
                  ),
                  AppSpacing.vGapSm,
                  VSOutlinedButton(
                    label: 'Download Receipt',
                    icon: Icons.download_rounded,
                    onPressed: () => context.showSnack('Receipt downloaded'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.result});

  final CreditPaymentResult? result;

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
          Text('TRANSACTION DETAILS',
              style: AppTypography.labelSmall
                  .copyWith(color: vs.textSecondary, letterSpacing: 1)),
          const Divider(height: AppSpacing.xl),
          _Row(
            label: 'Amount Paid',
            value: (result?.amountPaid ?? 0).asCurrency,
          ),
          const Divider(height: AppSpacing.xl),
          _Row(label: 'Payment Method', value: result?.method ?? '—'),
          const Divider(height: AppSpacing.xl),
          _Row(
            label: 'Transaction ID',
            value: result?.transactionId ?? '—',
            trailing: Icon(Icons.copy_rounded, size: 16, color: vs.trust),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.trailing});

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary)),
        Row(
          children: [
            Text(value, style: AppTypography.labelLarge),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.xs),
              trailing!,
            ],
          ],
        ),
      ],
    );
  }
}

class _FinancialStatusCard extends StatelessWidget {
  const _FinancialStatusCard({required this.result});

  final CreditPaymentResult result;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final account = result.account;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: vs.trustTint,
        borderRadius: AppRadius.brLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.credit_score_rounded, color: vs.trust, size: 18),
              AppSpacing.hGapSm,
              Text('FINANCIAL STATUS UPDATED',
                  style: AppTypography.labelMedium.copyWith(color: vs.trust)),
            ],
          ),
          AppSpacing.vGapMd,
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Available Credit',
                      style: AppTypography.bodySmall.copyWith(color: vs.trust)),
                  Text(account.available.asCurrency,
                      style: AppTypography.priceLarge),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Outstanding',
                      style: AppTypography.bodySmall.copyWith(color: vs.trust)),
                  Text(account.outstanding.asCurrency,
                      style: AppTypography.priceLarge.copyWith(
                          color: account.outstanding == 0 ? vs.success : null)),
                ],
              ),
            ],
          ),
          const Divider(height: AppSpacing.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Credit Limit',
                  style: AppTypography.bodyMedium.copyWith(color: vs.trust)),
              Text(account.creditLimit.asCurrency,
                  style: AppTypography.labelLarge),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScoreRewardCard extends StatelessWidget {
  const _ScoreRewardCard({required this.points});

  final int points;

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
      child: Row(
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(color: vs.offer, shape: BoxShape.circle),
            child: const Icon(Icons.emoji_events_rounded,
                color: AppColors.white, size: 22),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('VS Score Increased', style: AppTypography.titleMedium),
                Text('Great financial behavior!',
                    style: AppTypography.bodySmall
                        .copyWith(color: vs.textSecondary)),
              ],
            ),
          ),
          VSStatusChip(label: '+$points Points', tone: VSStatusTone.offer),
        ],
      ),
    );
  }
}
