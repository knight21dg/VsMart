import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../catalog/presentation/providers/catalog_providers.dart';
import '../../../cart/presentation/providers/cart_providers.dart';
import '../../domain/entities/order.dart';
import '../../domain/entities/order_enums.dart';
import '../../domain/entities/order_tracking.dart';
import '../providers/order_providers.dart';
import '../widgets/order_tracking_map.dart';
import '../widgets/order_widgets.dart';

/// Swiggy-style live order tracking: a full-screen map with an animated rider,
/// a floating back button, and a draggable order-summary sheet (status stats,
/// partner, bill). Once delivered the sheet collapses to just the order times
/// and a Reorder button.
class OrderTrackingScreen extends ConsumerStatefulWidget {
  const OrderTrackingScreen({super.key, required this.orderId});

  final String orderId;

  // Styled origin/destination for the route backdrop; the rider marker itself
  // is pinned to the backend's live agent coordinates when streaming.
  static const _store = LatLng(17.4435, 78.3772);

  static LatLng _destFor(String id) {
    final h = id.hashCode;
    return LatLng(
      17.4256 + ((h % 80) - 40) / 6000,
      78.4011 + (((h ~/ 80) % 80) - 40) / 6000,
    );
  }

  @override
  ConsumerState<OrderTrackingScreen> createState() =>
      _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(analyticsServiceProvider)
          .track('tracking_viewed', {'order': widget.orderId});
    });
    _poll = Timer.periodic(const Duration(seconds: 12), (_) {
      final t = ref.read(orderTrackingProvider(widget.orderId)).valueOrNull;
      if (t == null || t.currentStatus.isActive) {
        ref.invalidate(orderTrackingProvider(widget.orderId));
      } else {
        _poll?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trackingAsync = ref.watch(orderTrackingProvider(widget.orderId));
    return Scaffold(
      body: trackingAsync.when(
        loading: () => const VSLoadingView(),
        error: (e, _) => VSErrorView(
          failure: e is Failure ? e : null,
          onRetry: () =>
              ref.invalidate(orderTrackingProvider(widget.orderId)),
        ),
        data: (tracking) => _TrackingView(
          orderId: widget.orderId,
          tracking: tracking,
          store: OrderTrackingScreen._store,
          destination: OrderTrackingScreen._destFor(widget.orderId),
        ),
      ),
    );
  }
}

class _TrackingView extends StatelessWidget {
  const _TrackingView({
    required this.orderId,
    required this.tracking,
    required this.store,
    required this.destination,
  });

  final String orderId;
  final OrderTracking tracking;
  final LatLng store;
  final LatLng destination;

  @override
  Widget build(BuildContext context) {
    final sheetMin = MediaQuery.sizeOf(context).height * 0.30;
    return Stack(
      children: [
        Positioned.fill(
          child: OrderTrackingMap(
            store: store,
            destination: destination,
            status: tracking.currentStatus,
            agentPosition: tracking.agentLat != null && tracking.agentLng != null
                ? LatLng(tracking.agentLat!, tracking.agentLng!)
                : null,
            bottomPadding: sheetMin,
          ),
        ),
        // Floating back button.
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Align(
              alignment: Alignment.topLeft,
              child: _CircleButton(
                icon: Icons.arrow_back_rounded,
                onTap: () => context.pop(),
              ),
            ),
          ),
        ),
        DraggableScrollableSheet(
          initialChildSize: 0.34,
          minChildSize: 0.22,
          maxChildSize: 0.88,
          snap: true,
          snapSizes: const [0.34, 0.88],
          builder: (context, controller) => _SummarySheet(
            orderId: orderId,
            tracking: tracking,
            scrollController: controller,
          ),
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          height: 42,
          width: 42,
          child: Icon(icon, size: 20, color: context.colors.onSurface),
        ),
      ),
    );
  }
}

/// The draggable bottom sheet — the order's live summary over the map.
class _SummarySheet extends ConsumerWidget {
  const _SummarySheet({
    required this.orderId,
    required this.tracking,
    required this.scrollController,
  });

  final String orderId;
  final OrderTracking tracking;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    final order = ref.watch(orderByIdProvider(orderId)).valueOrNull;
    final delivered = tracking.currentStatus == OrderStatus.delivered;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: AppShadows.lg,
      ),
      clipBehavior: Clip.antiAlias,
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xl),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: vs.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          AppSpacing.vGapMd,
          if (delivered)
            _DeliveredSummary(order: order, tracking: tracking)
          else ...[
            _EtaHeadline(tracking: tracking),
            if (tracking.agentName != null) ...[
              AppSpacing.vGapMd,
              _PartnerRow(tracking: tracking),
            ],
            AppSpacing.vGapLg,
            Text('Order status', style: AppTypography.titleMedium),
            AppSpacing.vGapSm,
            VSOrderTimeline(entries: tracking.timeline),
            if (order != null) ...[
              const Divider(height: AppSpacing.xxl),
              _OrderItemsSummary(order: order),
            ],
          ],
        ],
      ),
    );
  }
}

/// Big "arriving" headline for an in-flight order.
class _EtaHeadline extends StatelessWidget {
  const _EtaHeadline({required this.tracking});

  final OrderTracking tracking;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final out = tracking.currentStatus == OrderStatus.outForDelivery;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tracking.etaLabel ?? tracking.currentStatus.label,
                style: AppTypography.headlineSmall,
              ),
              const SizedBox(height: 2),
              Text(
                out
                    ? 'Your order is on the way'
                    : 'We\'ll update you as it moves',
                style:
                    AppTypography.bodySmall.copyWith(color: vs.textSecondary),
              ),
            ],
          ),
        ),
        VSOrderStatusChip(status: tracking.currentStatus, dense: true),
      ],
    );
  }
}

/// Delivery partner row with a call action.
class _PartnerRow extends StatelessWidget {
  const _PartnerRow({required this.tracking});

  final OrderTracking tracking;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: vs.brandTint.withValues(alpha: 0.5),
        borderRadius: AppRadius.brLg,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: context.colors.surface,
            child: Icon(Icons.two_wheeler_rounded, color: vs.brand),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Delivery Partner',
                    style: AppTypography.bodySmall
                        .copyWith(color: vs.textSecondary)),
                Text(tracking.agentName!, style: AppTypography.titleMedium),
              ],
            ),
          ),
          IconButton.filledTonal(
            onPressed: () => context.showSnack(
              tracking.agentPhone != null
                  ? 'Calling ${tracking.agentName}…'
                  : 'Contact appears when the partner is near.',
            ),
            icon: const Icon(Icons.call_rounded),
          ),
        ],
      ),
    );
  }
}

/// Compact items + total for the in-flight order.
class _OrderItemsSummary extends StatelessWidget {
  const _OrderItemsSummary({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final items = order.items.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${order.itemCount} items', style: AppTypography.titleMedium),
            Text(order.summary.grandTotal.asCurrency,
                style: AppTypography.priceMedium),
          ],
        ),
        AppSpacing.vGapSm,
        for (final it in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Text('${it.quantity}×',
                    style: AppTypography.labelMedium.copyWith(color: vs.brand)),
                AppSpacing.hGapSm,
                Expanded(
                  child: Text(it.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMedium),
                ),
                Text(it.lineTotal.asCurrency,
                    style: AppTypography.bodySmall
                        .copyWith(color: vs.textSecondary)),
              ],
            ),
          ),
        if (order.items.length > items.length)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('+${order.items.length - items.length} more',
                style:
                    AppTypography.bodySmall.copyWith(color: vs.textSecondary)),
          ),
      ],
    );
  }
}

/// Post-delivery: just the order times + a Reorder button (+ items recap).
class _DeliveredSummary extends ConsumerWidget {
  const _DeliveredSummary({required this.order, required this.tracking});

  final Order? order;
  final OrderTracking tracking;

  DateTime? get _orderedAt {
    if (order != null) return order!.placedAt;
    return tracking.timeline.isNotEmpty ? tracking.timeline.first.at : null;
  }

  DateTime? get _deliveredAt {
    for (final e in tracking.timeline) {
      if (e.status == OrderStatus.delivered && e.at != null) return e.at;
    }
    return order?.estimatedDelivery;
  }

  Future<void> _reorder(BuildContext context, WidgetRef ref) async {
    final o = order;
    if (o == null) return;
    final cart = ref.read(cartControllerProvider.notifier);
    var added = 0;
    for (final item in o.items) {
      try {
        final p = await ref.read(productByIdProvider(item.productId).future);
        await cart.addProduct(p, quantity: item.quantity);
        added++;
      } catch (_) {/* skip unavailable */}
    }
    if (!context.mounted) return;
    context.showSnack(added > 0
        ? '$added item${added == 1 ? '' : 's'} added to cart'
        : 'Those items are unavailable right now');
    if (added > 0) context.goNamed(RouteNames.cart);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    final fmt = DateFormat('d MMM, h:mm a');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              height: 44,
              width: 44,
              decoration:
                  BoxDecoration(color: vs.successTint, shape: BoxShape.circle),
              child: Icon(Icons.check_rounded, color: vs.success),
            ),
            AppSpacing.hGapMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Delivered', style: AppTypography.titleLarge),
                  Text('Order #${tracking.orderId}',
                      style: AppTypography.bodySmall
                          .copyWith(color: vs.textSecondary)),
                ],
              ),
            ),
          ],
        ),
        AppSpacing.vGapLg,
        _TimeRow(
          icon: Icons.shopping_bag_outlined,
          label: 'Ordered at',
          value: _orderedAt == null ? '—' : fmt.format(_orderedAt!),
        ),
        AppSpacing.vGapSm,
        _TimeRow(
          icon: Icons.check_circle_outline_rounded,
          label: 'Delivered at',
          value: _deliveredAt == null ? '—' : fmt.format(_deliveredAt!),
        ),
        AppSpacing.vGapLg,
        VSButton(
          label: 'Reorder',
          icon: Icons.refresh_rounded,
          onPressed:
              order == null ? null : () => unawaited(_reorder(context, ref)),
        ),
      ],
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Row(
      children: [
        Icon(icon, size: 18, color: vs.textSecondary),
        AppSpacing.hGapMd,
        Text(label, style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary)),
        const Spacer(),
        Text(value, style: AppTypography.labelLarge),
      ],
    );
  }
}
