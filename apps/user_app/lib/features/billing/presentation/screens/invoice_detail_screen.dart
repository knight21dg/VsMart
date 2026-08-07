import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/l10n/status_labels.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../orders/data/invoice_service.dart';
import '../../domain/entities/invoice.dart';
import '../providers/billing_providers.dart';
import '../widgets/transaction_tile.dart';
import 'invoices_screen.dart';

/// Invoice detail (Phase 4F) — the full invoice with a link back to the order
/// and a download action.
class InvoiceDetailScreen extends ConsumerStatefulWidget {
  const InvoiceDetailScreen({super.key, required this.invoiceId});

  final String invoiceId;

  @override
  ConsumerState<InvoiceDetailScreen> createState() =>
      _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends ConsumerState<InvoiceDetailScreen> {
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(analyticsServiceProvider)
          .track('invoice_opened', {'id': widget.invoiceId});
    });
  }

  /// Fetch the branded PDF for this invoice's order and hand it to the platform
  /// print/share sheet. Reuses the same InvoiceService as the order screen.
  Future<void> _downloadInvoice(String orderCode) async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final bytes = await ref.read(invoiceServiceProvider).fetch(orderCode);
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'VS-Mart-Invoice-$orderCode',
      );
    } catch (_) {
      if (mounted) {
        context.showSnack(context.l10n.billingInvoiceLoadError, isError: true);
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final invoiceAsync = ref.watch(invoiceByIdProvider(widget.invoiceId));
    final orderCode = invoiceAsync.valueOrNull?.orderId;
    return Scaffold(
      appBar: VSAppBar(
        title: context.l10n.billingInvoice,
        actions: [
          IconButton(
            icon: _downloading
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_rounded),
            tooltip: context.l10n.commonDownload,
            onPressed: (orderCode == null || _downloading)
                ? null
                : () => _downloadInvoice(orderCode),
          ),
        ],
      ),
      body: invoiceAsync.when(
        loading: () => const VSLoadingView(),
        error: (e, _) => VSErrorView(
          failure: e is Failure ? e : null,
          onRetry: () => ref.invalidate(invoiceByIdProvider(widget.invoiceId)),
        ),
        data: (invoice) {
          if (invoice == null) {
            return VSEmptyState(
              title: context.l10n.billingInvoiceNotFound,
              icon: Icons.receipt_long_outlined,
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              // The by-id family derives from the invoices list — refetch it.
              ref.invalidate(invoicesProvider);
              await ref.read(invoiceByIdProvider(widget.invoiceId).future);
            },
            child: _Body(invoice: invoice),
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: AppSpacing.screen,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: AppRadius.brLg,
            border: Border.all(color: vs.border),
          ),
          child: Column(
            children: [
              Container(
                height: 64,
                width: 64,
                decoration:
                    BoxDecoration(color: vs.trustTint, shape: BoxShape.circle),
                child:
                    Icon(invoice.status.icon, color: vs.trust, size: 32),
              ),
              AppSpacing.vGapMd,
              Text(invoice.amount.asCurrency,
                  style: AppTypography.displayMedium
                      .copyWith(color: context.colors.onSurface)),
              AppSpacing.vGapXs,
              VSStatusChip(
                label: invoice.status.labelL10n(context.l10n),
                tone: invoiceTone(invoice.status),
              ),
            ],
          ),
        ),
        AppSpacing.vGapLg,
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: AppRadius.brLg,
            border: Border.all(color: vs.border),
          ),
          child: Column(
            children: [
              _Row(
                  label: context.l10n.billingInvoiceNumber,
                  value: invoice.invoiceId),
              const Divider(height: AppSpacing.xl),
              _Row(label: context.l10n.orderId, value: invoice.orderId),
              const Divider(height: AppSpacing.xl),
              _Row(
                  label: context.l10n.billingInvoiceDate,
                  value: DateFormat('d MMMM yyyy')
                      .format(invoice.generatedDate)),
              const Divider(height: AppSpacing.xl),
              _Row(
                  label: context.l10n.billingAmount,
                  value: invoice.amount.asCurrency),
            ],
          ),
        ),
        AppSpacing.vGapLg,
        VSOutlinedButton(
          label: context.l10n.billingViewOrder,
          icon: Icons.shopping_bag_outlined,
          onPressed: () => context.pushNamed(
            RouteNames.orderDetails,
            pathParameters: {'orderId': invoice.orderId},
          ),
        ),
      ],
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
