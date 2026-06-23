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
import '../../domain/entities/billing_enums.dart';
import '../../domain/entities/invoice.dart';
import '../providers/billing_providers.dart';
import '../widgets/transaction_tile.dart';

/// Maps an [InvoiceStatus] to the chip tone used across the list/detail.
VSStatusTone invoiceTone(InvoiceStatus status) => switch (status) {
      InvoiceStatus.paid => VSStatusTone.success,
      InvoiceStatus.pending => VSStatusTone.warning,
      InvoiceStatus.overdue => VSStatusTone.danger,
      InvoiceStatus.cancelled => VSStatusTone.neutral,
    };

/// Invoices list (Phase 4F) — every credit-funded order invoice.
class InvoicesScreen extends ConsumerWidget {
  const InvoicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoicesAsync = ref.watch(invoicesProvider);
    return Scaffold(
      appBar: const VSAppBar(title: 'Invoices'),
      body: invoicesAsync.when(
        loading: () => const VSLoadingView(),
        error: (e, _) => VSErrorView(
          failure: e is Failure ? e : null,
          onRetry: () => ref.invalidate(invoicesProvider),
        ),
        data: (invoices) {
          if (invoices.isEmpty) {
            return const VSEmptyState(
              title: 'No invoices yet',
              message: 'Invoices for your credit orders will appear here.',
              icon: Icons.receipt_long_outlined,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(invoicesProvider),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: AppSpacing.screen,
              itemCount: invoices.length,
              separatorBuilder: (_, __) => AppSpacing.vGapMd,
              itemBuilder: (_, i) => _InvoiceCard(invoice: invoices[i]),
            ),
          );
        },
      ),
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      onTap: () => context.pushNamed(
        RouteNames.invoiceDetail,
        pathParameters: {'id': invoice.invoiceId},
      ),
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
                  BoxDecoration(color: vs.trustTint, shape: BoxShape.circle),
              child: Icon(invoice.status.icon, color: vs.trust, size: 22),
            ),
            AppSpacing.hGapMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(invoice.invoiceId, style: AppTypography.titleMedium),
                  Text(
                    'Order ${invoice.orderId} • '
                    '${DateFormat('d MMM yyyy').format(invoice.generatedDate)}',
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
                Text(invoice.amount.asCurrency,
                    style: AppTypography.labelLarge),
                AppSpacing.vGapXs,
                VSStatusChip(
                  label: invoice.status.label,
                  tone: invoiceTone(invoice.status),
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
