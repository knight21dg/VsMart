import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/billing_enums.dart';
import '../../domain/entities/repayment.dart';
import '../providers/billing_providers.dart';

/// Maps a repayment's [TransactionStatus] to a chip tone.
VSStatusTone _statusTone(TransactionStatus status) => switch (status) {
      TransactionStatus.completed => VSStatusTone.success,
      TransactionStatus.pending => VSStatusTone.warning,
      TransactionStatus.failed => VSStatusTone.danger,
      TransactionStatus.reversed => VSStatusTone.neutral,
    };

/// Payment History (Phase 4G) — every repayment made, newest first. Tapping a
/// row reveals the receipt detail.
class PaymentHistoryScreen extends ConsumerWidget {
  const PaymentHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(paymentHistoryProvider);
    return Scaffold(
      appBar: const VSAppBar(title: 'Payment History'),
      body: historyAsync.when(
        loading: () => const VSLoadingView(),
        error: (e, _) => VSErrorView(
          failure: e is Failure ? e : null,
          onRetry: () => ref.invalidate(paymentHistoryProvider),
        ),
        data: (history) {
          if (history.isEmpty) {
            return const VSEmptyState(
              title: 'No payments yet',
              message: 'Your repayments will show up here.',
              icon: Icons.history_rounded,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(paymentHistoryProvider),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: AppSpacing.screen,
              itemCount: history.length,
              separatorBuilder: (_, __) => AppSpacing.vGapMd,
              itemBuilder: (_, i) => _PaymentCard(payment: history[i]),
            ),
          );
        },
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.payment});

  final Repayment payment;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      onTap: () => _showReceipt(context, payment),
      borderRadius: AppRadius.brLg,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: AppRadius.brLg,
          border: Border.all(color: vs.border),
        ),
        child: Row(
          children: [
            Container(
              height: 44,
              width: 44,
              decoration:
                  BoxDecoration(color: vs.successTint, shape: BoxShape.circle),
              child: Icon(Icons.south_rounded, color: vs.success, size: 22),
            ),
            AppSpacing.hGapMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(payment.method.label, style: AppTypography.titleMedium),
                  Text(
                    DateFormat('d MMM yyyy • h:mm a').format(payment.date),
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
                Text('− ${payment.amount.asCurrency}',
                    style: AppTypography.labelLarge
                        .copyWith(color: vs.success)),
                AppSpacing.vGapXs,
                VSStatusChip(
                  label: payment.status.label,
                  tone: _statusTone(payment.status),
                  dense: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

void _showReceipt(BuildContext context, Repayment payment) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: context.colors.surface,
    builder: (_) => _ReceiptSheet(payment: payment),
  );
}

class _ReceiptSheet extends StatelessWidget {
  const _ReceiptSheet({required this.payment});

  final Repayment payment;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                height: 56,
                width: 56,
                decoration: BoxDecoration(
                    color: vs.successTint, shape: BoxShape.circle),
                child: Icon(Icons.receipt_long_rounded,
                    color: vs.success, size: 28),
              ),
            ),
            AppSpacing.vGapMd,
            Center(
              child: Text(payment.amount.asCurrency,
                  style: AppTypography.headlineLarge),
            ),
            AppSpacing.vGapXl,
            _Row(label: 'Status', value: payment.status.label),
            const Divider(height: AppSpacing.xl),
            _Row(label: 'Method', value: payment.method.label),
            const Divider(height: AppSpacing.xl),
            _Row(
                label: 'Date',
                value: DateFormat('d MMMM yyyy, h:mm a').format(payment.date)),
            const Divider(height: AppSpacing.xl),
            _Row(label: 'Reference', value: payment.reference ?? payment.id),
            AppSpacing.vGapLg,
            VSOutlinedButton(
              label: 'Download Receipt',
              icon: Icons.download_rounded,
              onPressed: () {
                Navigator.of(context).pop();
                context.showSnack('Receipt downloaded');
              },
            ),
          ],
        ),
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
