import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/billing_enums.dart';
import '../../domain/entities/repayment.dart';
import '../providers/billing_providers.dart';

/// Post-repayment confirmation (Phase 4H) — receipt details plus the refreshed
/// credit standing. Reads [lastRepaymentProvider] for the receipt and the
/// ledger-derived providers for the new balance.
class RepaymentSuccessScreen extends ConsumerWidget {
  const RepaymentSuccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    final payment = ref.watch(lastRepaymentProvider);
    final available = ref.watch(availableCreditProvider);
    final outstanding = ref.watch(outstandingBalanceProvider);

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
                  Text('Your repayment has been recorded.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium
                          .copyWith(color: vs.textSecondary)),
                  AppSpacing.vGapXl,
                  if (payment != null) _DetailsCard(payment: payment),
                  AppSpacing.vGapLg,
                  _BalanceCard(
                    available: available.valueOrNull ?? 0,
                    outstanding: outstanding.valueOrNull ?? 0,
                  ),
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
  const _DetailsCard({required this.payment});

  final Repayment payment;

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
          _Row(label: 'Amount Paid', value: payment.amount.asCurrency),
          const Divider(height: AppSpacing.xl),
          _Row(label: 'Payment Method', value: payment.method.label),
          const Divider(height: AppSpacing.xl),
          _Row(
              label: 'Date',
              value: DateFormat('d MMM yyyy, h:mm a').format(payment.date)),
          const Divider(height: AppSpacing.xl),
          _Row(label: 'Transaction ID', value: payment.id),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.available, required this.outstanding});

  final num available;
  final num outstanding;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
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
              Text('CREDIT UPDATED',
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
                  Text(available.asCurrency, style: AppTypography.priceLarge),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Outstanding',
                      style: AppTypography.bodySmall.copyWith(color: vs.trust)),
                  Text(outstanding.asCurrency,
                      style: AppTypography.priceLarge.copyWith(
                          color: outstanding == 0 ? vs.success : null)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary)),
        Flexible(
          child: Text(value,
              textAlign: TextAlign.end, style: AppTypography.labelLarge),
        ),
      ],
    );
  }
}
