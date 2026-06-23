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
import '../../domain/entities/billing_enums.dart';
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(analyticsServiceProvider)
          .track('invoice_opened', {'id': widget.invoiceId});
    });
  }

  @override
  Widget build(BuildContext context) {
    final invoiceAsync = ref.watch(invoiceByIdProvider(widget.invoiceId));
    return Scaffold(
      appBar: VSAppBar(
        title: 'Invoice',
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Download',
            onPressed: () => context.showSnack('Invoice downloaded'),
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
            return const VSEmptyState(
              title: 'Invoice not found',
              icon: Icons.receipt_long_outlined,
            );
          }
          return _Body(invoice: invoice);
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
                label: invoice.status.label,
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
              _Row(label: 'Invoice Number', value: invoice.invoiceId),
              const Divider(height: AppSpacing.xl),
              _Row(label: 'Order ID', value: invoice.orderId),
              const Divider(height: AppSpacing.xl),
              _Row(
                  label: 'Invoice Date',
                  value: DateFormat('d MMMM yyyy')
                      .format(invoice.generatedDate)),
              const Divider(height: AppSpacing.xl),
              _Row(label: 'Amount', value: invoice.amount.asCurrency),
            ],
          ),
        ),
        AppSpacing.vGapLg,
        VSOutlinedButton(
          label: 'View Order',
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
