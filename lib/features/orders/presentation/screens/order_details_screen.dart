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
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../data/invoice_service.dart';
import '../../domain/entities/order.dart';
import '../../domain/entities/order_enums.dart';
import '../providers/order_providers.dart';
import '../widgets/order_widgets.dart';

/// Full order detail: timeline, items, address, payment, billing, support.
class OrderDetailsScreen extends ConsumerStatefulWidget {
  const OrderDetailsScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<OrderDetailsScreen> createState() =>
      _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends ConsumerState<OrderDetailsScreen> {
  bool _invoiceBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(analyticsServiceProvider)
          .track('order_viewed', {'order': widget.orderId});
    });
  }

  Future<void> _downloadInvoice() async {
    setState(() => _invoiceBusy = true);
    try {
      final bytes = await ref.read(invoiceServiceProvider).fetch(widget.orderId);
      ref.read(analyticsServiceProvider).track('invoice_opened', {'order': widget.orderId});
      // Native preview with print / save-to-PDF / share built in.
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'VS-Mart-Invoice-${widget.orderId}',
      );
    } catch (_) {
      if (mounted) context.showSnack('Could not load the invoice', isError: true);
    } finally {
      if (mounted) setState(() => _invoiceBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderByIdProvider(widget.orderId));
    return Scaffold(
      appBar: VSAppBar(
        title: 'Order Details',
        actions: [
          IconButton(
            tooltip: 'Invoice',
            onPressed: _invoiceBusy ? null : _downloadInvoice,
            icon: _invoiceBusy
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.receipt_long_rounded),
          ),
        ],
      ),
      body: orderAsync.when(
        loading: () => const VSLoadingView(),
        error: (e, _) => VSErrorView(
          failure: e is Failure ? e : null,
          onRetry: () => ref.invalidate(orderByIdProvider(widget.orderId)),
        ),
        data: (order) => _Body(order: order),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.order});

  final Order order;

  bool get _cancellable =>
      order.status == OrderStatus.pending ||
      order.status == OrderStatus.confirmed ||
      order.status == OrderStatus.packed;

  Future<void> _cancel(WidgetRef ref, BuildContext context) async {
    final result =
        await ref.read(orderRepositoryProvider).cancelOrder(order.id);
    if (!context.mounted) return;
    result.fold(
      (_) => context.showSnack('Could not cancel the order', isError: true),
      (_) {
        ref
            .read(analyticsServiceProvider)
            .track('order_cancelled', {'order': order.id});
        ref.invalidate(orderByIdProvider(order.id));
        ref.invalidate(ordersProvider);
        context.showSnack('Order cancelled');
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    return ListView(
      padding: AppSpacing.screen,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Order #${order.id}', style: AppTypography.titleLarge),
                Text(DateFormat('d MMM yyyy, h:mm a').format(order.placedAt),
                    style: AppTypography.bodySmall
                        .copyWith(color: vs.textSecondary)),
              ],
            ),
            VSOrderStatusChip(status: order.status),
          ],
        ),
        AppSpacing.vGapLg,
        if (order.timeline.isNotEmpty) ...[
          _Card(title: 'Order Timeline', child: VSOrderTimeline(entries: order.timeline)),
          AppSpacing.vGapMd,
        ],
        _Card(
          title: 'Items',
          child: Column(
            children: [
              for (final item in order.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: [
                      Container(
                        height: 40,
                        width: 40,
                        decoration: BoxDecoration(
                            color: vs.brandTint, borderRadius: AppRadius.brSm),
                        child: Icon(Icons.shopping_basket_rounded,
                            size: 20, color: vs.brand),
                      ),
                      AppSpacing.hGapMd,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${item.name}  ×${item.quantity}',
                                style: AppTypography.bodyMedium),
                            Text(item.unit,
                                style: AppTypography.bodySmall
                                    .copyWith(color: vs.textSecondary)),
                          ],
                        ),
                      ),
                      Text(item.lineTotal.asCurrency,
                          style: AppTypography.labelLarge),
                    ],
                  ),
                ),
            ],
          ),
        ),
        AppSpacing.vGapMd,
        _Card(
          title: 'Delivery Address',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(order.address.name, style: AppTypography.labelLarge),
              Text(order.address.formatted,
                  style: AppTypography.bodySmall
                      .copyWith(color: vs.textSecondary)),
              if (order.address.phone.isNotEmpty)
                Text(order.address.phone,
                    style: AppTypography.bodySmall
                        .copyWith(color: vs.textSecondary)),
            ],
          ),
        ),
        AppSpacing.vGapMd,
        _Card(
          title: 'Payment',
          child: Column(
            children: [
              _kv(context, 'Method', order.payment.method.label),
              AppSpacing.vGapSm,
              _kv(context, 'Status', order.payment.status.label),
              if (order.payment.creditUsed > 0) ...[
                AppSpacing.vGapSm,
                _kv(context, 'Credit Used',
                    order.payment.creditUsed.asCurrency),
              ],
            ],
          ),
        ),
        AppSpacing.vGapMd,
        _Card(title: 'Billing', child: VSOrderSummary(summary: order.summary)),
        AppSpacing.vGapMd,
        Row(
          children: [
            if (order.status.isActive)
              Expanded(
                child: VSButton(
                  label: 'Track Order',
                  onPressed: () => context.pushNamed(
                    RouteNames.orderTracking,
                    pathParameters: {'orderId': order.id},
                  ),
                ),
              ),
            if (order.status.isActive) AppSpacing.hGapMd,
            Expanded(
              child: VSOutlinedButton(
                label: 'Need Help?',
                onPressed: () => context.pushNamed(RouteNames.support),
              ),
            ),
          ],
        ),
        if (_cancellable) ...[
          AppSpacing.vGapMd,
          VSOutlinedButton(
            label: 'Cancel Order',
            color: vs.danger,
            onPressed: () => _cancel(ref, context),
          ),
        ],
        if (order.status == OrderStatus.delivered) ...[
          AppSpacing.vGapMd,
          VSOutlinedButton(
            label: 'Return / Refund',
            icon: Icons.assignment_return_outlined,
            onPressed: () => context.pushNamed(
              RouteNames.requestReturn,
              extra: order.id,
            ),
          ),
        ],
      ],
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    final vs = context.vsColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(k,
            style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary)),
        Text(v, style: AppTypography.labelLarge),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

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
          Text(title, style: AppTypography.titleMedium),
          const Divider(height: AppSpacing.lg),
          child,
        ],
      ),
    );
  }
}
