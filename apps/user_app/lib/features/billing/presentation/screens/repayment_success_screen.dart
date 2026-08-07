import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/app_error_presenter.dart';
import '../../../../core/errors/error_handler.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/l10n/status_labels.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../data/receipt_service.dart';
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
                  Text(context.l10n.billingPaymentSuccessful,
                      textAlign: TextAlign.center,
                      style: AppTypography.headlineLarge),
                  AppSpacing.vGapSm,
                  Text(context.l10n.billingRepaymentRecorded,
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
                    label: context.l10n.billingBackToDashboard,
                    onPressed: () =>
                        context.goNamed(RouteNames.creditDashboard),
                  ),
                  // Only offer the receipt when there's a real payment id to fetch
                  // one for. This button used to fire a "Receipt downloaded"
                  // snackbar and fetch NOTHING — on the one screen a customer most
                  // wants proof of payment.
                  if (payment != null && payment.id.isNotEmpty) ...[
                    AppSpacing.vGapSm,
                    _DownloadReceiptButton(paymentId: payment.id),
                  ],
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
          Text(context.l10n.creditTransactionDetails.toUpperCase(),
              style: AppTypography.labelSmall
                  .copyWith(color: vs.textSecondary, letterSpacing: 1)),
          const Divider(height: AppSpacing.xl),
          _Row(
              label: context.l10n.billingAmountPaid,
              value: payment.amount.asCurrency),
          const Divider(height: AppSpacing.xl),
          _Row(
              label: context.l10n.checkoutPaymentMethod,
              value: payment.method.labelL10n(context.l10n)),
          const Divider(height: AppSpacing.xl),
          _Row(
              label: context.l10n.billingDate,
              value: DateFormat('d MMM yyyy, h:mm a').format(payment.date)),
          const Divider(height: AppSpacing.xl),
          _Row(label: context.l10n.creditTransactionId, value: payment.id),
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
              Text(context.l10n.billingCreditUpdated.toUpperCase(),
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
                  Text(context.l10n.creditAvailable,
                      style: AppTypography.bodySmall.copyWith(color: vs.trust)),
                  Text(available.asCurrency, style: AppTypography.priceLarge),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(context.l10n.creditOutstanding,
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

/// Fetches and opens the real repayment receipt PDF (native preview with
/// print / save / share). Mirrors the receipt button on Payment History — the
/// same `ReceiptService.fetch` path, not a snackbar.
class _DownloadReceiptButton extends ConsumerStatefulWidget {
  const _DownloadReceiptButton({required this.paymentId});

  final String paymentId;

  @override
  ConsumerState<_DownloadReceiptButton> createState() =>
      _DownloadReceiptButtonState();
}

class _DownloadReceiptButtonState
    extends ConsumerState<_DownloadReceiptButton> {
  bool _busy = false;

  Future<void> _open() async {
    setState(() => _busy = true);
    try {
      final bytes =
          await ref.read(receiptServiceProvider).fetch(widget.paymentId);
      ref
          .read(analyticsServiceProvider)
          .track('receipt_opened', {'payment': widget.paymentId});
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'VS-Mart-Receipt-${widget.paymentId}',
      );
    } catch (e) {
      if (mounted) {
        presentFailure(context, ref, ErrorHandler.handle(e), onRetry: _open);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return VSOutlinedButton(
      label: context.l10n.billingDownloadReceipt,
      icon: Icons.download_rounded,
      isLoading: _busy,
      onPressed: _busy ? null : _open,
    );
  }
}
