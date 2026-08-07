import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/app_error_presenter.dart';
import '../../../../core/errors/error_handler.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/l10n/status_labels.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../reviews/presentation/screens/write_review_screen.dart';
import '../../data/invoice_service.dart';
import '../../domain/entities/order.dart';
import '../../domain/entities/order_enums.dart';
import '../providers/order_providers.dart';
import '../widgets/order_widgets.dart';
import '../widgets/delivery_otp_card.dart';
import '../widgets/order_feedback_card.dart';
import '../widgets/reorder_sheet.dart';

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
    } catch (e) {
      if (mounted) {
        presentFailure(context, ref, ErrorHandler.handle(e),
            onRetry: _downloadInvoice);
      }
    } finally {
      if (mounted) setState(() => _invoiceBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderAsync = ref.watch(orderByIdProvider(widget.orderId));
    // A tax invoice exists only for a DELIVERED and PAID order — the button
    // appears exactly when the server would produce one (it now refuses
    // anything earlier), instead of offering a download that errors.
    final order = orderAsync.valueOrNull;
    final invoiceReady = order != null &&
        order.status.isCompleted &&
        order.payment.status == PaymentStatus.paid;
    return Scaffold(
      appBar: VSAppBar(
        title: context.l10n.orderDetailsTitle,
        actions: [
          if (invoiceReady)
            IconButton(
              tooltip: context.l10n.billingInvoice,
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

  // Mirrors the backend cancel guard (pending|confirmed). Previously also offered
  // Cancel on `packed`, which the server rejects with ORDER_NOT_CANCELLABLE.
  bool get _cancellable => order.status.isCancellable;

  /// Re-add a finished order's items to the cart, after a review step.
  ///
  /// Lives here (rather than on the tracking screen's delivered summary) because a
  /// completed order now opens THIS screen instead of a live map, so the action
  /// followed the journey.
  ///
  /// This used to fetch every product one at a time and add `product` — dropping
  /// the VARIANT, so reordering a 5 kg pack quietly added the base SKU at a
  /// different price. Failures were swallowed per item, so the customer was told
  /// "3 items added" with no idea which two were missing. The sheet asks the
  /// server for one authoritative plan and shows what's coming back.
  Future<void> _reorder(WidgetRef ref, BuildContext context, Order order) async {
    final added = await showReorderSheet(context, orderCode: order.id);
    if (added && context.mounted) context.goNamed(RouteNames.cart);
  }

  /// Confirms the irreversible cancel before firing it. The backend accepts no
  /// reason on this endpoint, so we only gate on a yes/no — nothing invented.
  Future<void> _confirmCancel(WidgetRef ref, BuildContext context) async {
    final vs = context.vsColors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.ordersCancelConfirmTitle),
        content: Text(context.l10n.ordersCancelConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.ordersKeepOrder),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: vs.danger),
            child: Text(context.l10n.orderCancel),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _cancel(ref, context);
  }

  Future<void> _cancel(WidgetRef ref, BuildContext context) async {
    final result =
        await ref.read(orderRepositoryProvider).cancelOrder(order.id);
    if (!context.mounted) return;
    result.fold(
      (failure) => presentFailure(context, ref, failure,
          onRetry: () => _cancel(ref, context)),
      (_) {
        ref
            .read(analyticsServiceProvider)
            .track('order_cancelled', {'order': order.id});
        ref.invalidate(orderByIdProvider(order.id));
        ref.invalidate(ordersProvider);
        context.showSnack(context.l10n.ordersCancelled);
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(orderByIdProvider(order.id));
        await ref.read(orderByIdProvider(order.id).future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: AppSpacing.screen,
        children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.ordersOrderNumber(order.id),
                    style: AppTypography.titleLarge),
                Text(DateFormat('d MMM yyyy, h:mm a').format(order.placedAt),
                    style: AppTypography.bodySmall
                        .copyWith(color: vs.textSecondary)),
              ],
            ),
            VSOrderStatusChip(status: order.status),
          ],
        ),
        AppSpacing.vGapLg,
        // Asks only once the delivery has completed (the card hides itself
        // otherwise). This is VS Mart's only rating surface — products carry none.
        // Rider at the door → the handover code belongs HERE too, not only on
        // the tracking screen (and never just in the notification inbox).
        if (order.status.isDispatched) _DeliveryOtpSection(orderId: order.id),
        OrderFeedbackCard(orderCode: order.id),
        if (order.timeline.isNotEmpty) ...[
          _Card(title: context.l10n.ordersTimeline, child: VSOrderTimeline(entries: order.timeline)),
          AppSpacing.vGapMd,
        ],
        _Card(
          title: context.l10n.orderItems,
          child: Column(
            children: [
              for (final item in order.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: [
                      // The order line already carries its image; every item was
                      // rendering the same generic basket glyph, so a ten-line
                      // order was a wall of identical icons. Falls back to the
                      // glyph only when the line genuinely has no picture.
                      ClipRRect(
                        borderRadius: AppRadius.brSm,
                        child: SizedBox(
                          height: 40,
                          width: 40,
                          child: (item.imageUrl ?? '').isEmpty
                              ? Container(
                                  color: vs.brandTint,
                                  child: Icon(Icons.shopping_basket_rounded,
                                      size: 20, color: vs.brand),
                                )
                              : VSNetworkImage(
                                  url: item.imageUrl!, fit: BoxFit.cover),
                        ),
                      ),
                      AppSpacing.hGapMd,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                context.l10n.ordersItemQuantity(
                                    item.name, item.quantity),
                                style: AppTypography.bodyMedium),
                            Row(
                              children: [
                                Text(item.unit,
                                    style: AppTypography.bodySmall
                                        .copyWith(color: vs.textSecondary)),
                                // Unit price was missing entirely, so a customer
                                // could see "Rice × 3 — ₹300" with no way to check
                                // what one cost.
                                Text(' · ${item.price.asCurrency}',
                                    style: AppTypography.bodySmall
                                        .copyWith(color: vs.textSecondary)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Text(item.lineTotal.asCurrency,
                          style: AppTypography.labelLarge),
                      // Review what you actually bought. The backend already
                      // auto-approves a review from a delivered order as a
                      // VERIFIED PURCHASE — but nothing in the app ever opened
                      // that path, so the full-screen form sat unreachable and
                      // the verified-purchase badge could only be earned by
                      // reviewing from the product page.
                      if (order.status.isCompleted) ...[
                        AppSpacing.hGapSm,
                        IconButton(
                          icon: const Icon(Icons.rate_review_outlined, size: 20),
                          tooltip: context.l10n.reviewsWriteReview,
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => WriteReviewScreen(
                                productId: item.productId,
                                productName: item.name,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        AppSpacing.vGapMd,
        _Card(
          title: context.l10n.orderDeliveryDetails,
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
          title: context.l10n.ordersPayment,
          child: Column(
            children: [
              _kv(context, context.l10n.billingMethod,
                  order.payment.method.labelL10n(context.l10n)),
              AppSpacing.vGapSm,
              _kv(context, context.l10n.billingStatus,
                  order.payment.status.labelL10n(context.l10n)),
              if (order.payment.creditUsed > 0) ...[
                AppSpacing.vGapSm,
                _kv(context, context.l10n.ordersCreditUsed,
                    order.payment.creditUsed.asCurrency),
              ],
              if (order.payment.amountPaid > 0) ...[
                AppSpacing.vGapSm,
                _kv(context, context.l10n.ordersAmountPaid,
                    order.payment.amountPaid.asCurrency),
              ],
              // A cancelled order used to end at "Cancelled" with no word on the
              // money. Say whether the refund has actually been paid — and when it
              // hasn't yet, say that too rather than showing nothing.
              if (order.payment.hasRefund) ...[
                AppSpacing.vGapSm,
                _kv(context, context.l10n.ordersAmountRefunded,
                    order.payment.amountRefunded.asCurrency),
              ] else if (order.status.isCancelled &&
                  order.payment.amountPaid > 0) ...[
                AppSpacing.vGapSm,
                _kv(context, context.l10n.ordersAmountRefunded,
                    context.l10n.ordersRefundPending),
              ],
            ],
          ),
        ),
        AppSpacing.vGapMd,
        _Card(title: context.l10n.orderBillDetails, child: VSOrderSummary(summary: order.summary)),
        AppSpacing.vGapMd,
        Row(
          children: [
            // Track only once dispatched; a delivered or cancelled order shows
            // its details (this screen) instead.
            if (order.status.isTrackable)
              Expanded(
                child: VSButton(
                  label: context.l10n.ordersTrack,
                  onPressed: () => context.pushNamed(
                    RouteNames.orderTracking,
                    pathParameters: {'orderId': order.id},
                  ),
                ),
              ),
            // "Need help?" is HIDDEN (not removed) until the support flow ships
            // in a later update — flip this back on to restore it.
            // if (order.status.isTrackable) AppSpacing.hGapMd,
            // Expanded(
            //   child: VSOutlinedButton(
            //     label: context.l10n.orderNeedHelp,
            //     onPressed: () => context.pushNamed(RouteNames.support),
            //   ),
            // ),
          ],
        ),
        if (_cancellable) ...[
          AppSpacing.vGapMd,
          VSOutlinedButton(
            label: context.l10n.orderCancel,
            color: vs.danger,
            onPressed: () => _confirmCancel(ref, context),
          ),
        ],
        if (order.status == OrderStatus.delivered) ...[
          AppSpacing.vGapMd,
          VSOutlinedButton(
            label: context.l10n.returnRequestTitle,
            icon: Icons.assignment_return_outlined,
            onPressed: () => context.pushNamed(
              RouteNames.requestReturn,
              extra: order.id,
            ),
          ),
        ],
        // Reorder lives here now. A finished order no longer opens the tracking
        // screen (there is nothing to track), and this is where that journey
        // lands — so the action came with it rather than being lost.
        if (order.status.isCompleted) ...[
          AppSpacing.vGapMd,
          VSOutlinedButton(
            label: context.l10n.ordersReorder,
            icon: Icons.refresh_rounded,
            onPressed: () => _reorder(ref, context, order),
          ),
        ],
      ],
      ),
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


/// The delivery OTP block on order details — only while the rider is out and
/// the code is still spendable (the tracking payload clears it otherwise).
class _DeliveryOtpSection extends ConsumerWidget {
  const _DeliveryOtpSection({required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracking = ref.watch(orderTrackingProvider(orderId)).valueOrNull;
    if (tracking == null || !tracking.hasDeliveryOtp) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: DeliveryOtpCard(code: tracking.deliveryOtp),
    );
  }
}
