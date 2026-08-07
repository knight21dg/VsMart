import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../domain/entities/order.dart';
import '../providers/live_tracking_provider.dart';
import '../../domain/entities/order_enums.dart';
import '../../domain/entities/order_tracking.dart';
import '../providers/order_providers.dart';
import '../widgets/delivery_otp_card.dart';
import '../widgets/order_tracking_map.dart';
import '../widgets/order_widgets.dart';

/// Live order tracking: a full-screen map with the rider's real position, a
/// floating back button, and a draggable order-summary sheet (ETA, partner,
/// timeline, bill).
///
/// Only reachable while the order is genuinely in flight. A completed or failed
/// order is redirected to the order details screen — there is nothing to track,
/// and showing a map for one misrepresents what is happening.
class OrderTrackingScreen extends ConsumerStatefulWidget {
  const OrderTrackingScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<OrderTrackingScreen> createState() =>
      _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen>
    with WidgetsBindingObserver {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(analyticsServiceProvider)
          .track('tracking_viewed', {'order': widget.orderId});
    });
    _startPoll();
  }

  void _startPoll() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 12), (_) => _tick());
  }

  /// Whether the order can still move on its own, so another poll could tell the
  /// customer something new.
  bool _shouldPoll() {
    final async = ref.read(orderTrackingProvider(widget.orderId));
    // Stop on a hard error too. `valueOrNull` is also null in the error state,
    // so the old `t == null` kept re-firing every 12s forever against an
    // endpoint that was never going to succeed (order purged, token revoked).
    if (async.hasError) return false;
    final t = async.valueOrNull;
    // `isActive` is true for failedDelivery, so a failed delivery awaiting a
    // store decision polled forever.
    return t == null || t.currentStatus.isPreparing || t.currentStatus.isTrackable;
  }

  void _tick() {
    if (_shouldPoll()) {
      ref.invalidate(orderTrackingProvider(widget.orderId));
    } else {
      _poll?.cancel();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A 12s timer does not stop when the app leaves the foreground, so tracking
    // an order and switching apps kept hitting the network every 12 seconds —
    // draining battery and data to refresh a screen nobody was looking at.
    if (state == AppLifecycleState.resumed) {
      if (!_shouldPoll()) return;
      // Catch up on everything missed while backgrounded before resuming cadence.
      ref.invalidate(orderTrackingProvider(widget.orderId));
      _startPoll();
    } else {
      _poll?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
        data: (tracking) {
          final status = tracking.currentStatus;
          // A FINISHED order has nothing to track — send the customer to its
          // details instead. This is the last line of defence: the Track buttons
          // are already gated, but a push-notification deep link or a stale
          // back-stack entry reaches this route directly, and used to render a
          // live map (with a simulated rider) for an order that was delivered
          // days ago or cancelled outright.
          if (status.isCompleted || status.isFailed) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              context.pushReplacementNamed(
                RouteNames.orderDetails,
                pathParameters: {'orderId': widget.orderId},
              );
            });
            return const VSLoadingView();
          }
          return _TrackingView(
            orderId: widget.orderId,
            tracking: tracking,
            // Real trip endpoints only — no fabricated coordinates. Store is null
            // when the serving store has no location set; the map then simply
            // omits the pickup marker instead of inventing one.
            store: tracking.hasStore
                ? LatLng(tracking.storeLat!, tracking.storeLng!)
                : null,
            destination: tracking.hasDestination
                ? LatLng(tracking.destLat!, tracking.destLng!)
                : null,
          );
        },
      ),
    );
  }
}

class _TrackingView extends ConsumerWidget {
  const _TrackingView({
    required this.orderId,
    required this.tracking,
    required this.store,
    required this.destination,
  });

  final String orderId;
  final OrderTracking tracking;
  final LatLng? store;
  final LatLng? destination;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sheetMin = MediaQuery.sizeOf(context).height * 0.30;
    final status = tracking.currentStatus;
    // LIVE MAP ONLY ONCE THE PARCEL IS WITH A RIDER.
    //
    // The map used to be gated purely on having destination coordinates, so an
    // order placed thirty seconds ago — or a cancelled one — opened a full-screen
    // map with a simulated rider driving toward the customer. Nothing had been
    // dispatched; the movement was local animation. Before dispatch the customer
    // sees the preparation progress instead, which is the honest information.
    final showMap = status.isTrackable;
    // Only subscribe to the live socket when there is genuinely a rider moving.
    final live = showMap
        ? ref.watch(liveTrackingProvider(orderId)).valueOrNull
        : null;
    final LatLng? agentPosition = live != null
        ? LatLng(live.lat, live.lng)
        : (showMap && tracking.agentLat != null && tracking.agentLng != null
            ? LatLng(tracking.agentLat!, tracking.agentLng!)
            : null);
    final dest = destination;
    return Stack(
      children: [
        Positioned.fill(
          // The map needs a real delivery address to anchor on. Without one (an
          // order whose address has no coordinates) we show a calm placeholder
          // rather than a map pinned to a made-up point.
          child: !showMap
              // Not dispatched (or already finished) — no live map to show.
              ? _PreDispatchBackdrop(status: status)
              : dest != null
                  ? OrderTrackingMap(
                      store: store,
                      destination: dest,
                      status: status,
                      agentPosition: agentPosition,
                      bottomPadding: sheetMin,
                      // Keep the real road ETA the map fetched — the headline
                      // prefers it over the backend's straight-line estimate.
                      onEta: (eta) => ref
                          .read(routeEtaProvider(orderId).notifier)
                          .state = eta,
                    )
                  // Genuinely out for delivery, but the address has no pinned
                  // coordinates to anchor a map on.
                  : const _MapUnavailable(),
        ),
        // Floating back button.
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                _CircleButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => context.pop(),
                ),
                const Spacer(),
                // Same live-trip chip the rider sees on the agent map — the two
                // ends of the delivery now share one design language.
                _LiveEtaChip(tracking: tracking, orderId: orderId),
              ],
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

/// White pill with the live ETA (road-route figure when the map has fetched
/// one, else the backend estimate) — mirrors the agent map's trip chip.
class _LiveEtaChip extends ConsumerWidget {
  const _LiveEtaChip({required this.tracking, required this.orderId});

  final OrderTracking tracking;
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routeEta = ref.watch(routeEtaProvider(orderId));
    final label = (routeEta != null && routeEta.isNotEmpty)
        ? routeEta
        : tracking.etaLabel;
    if (label == null || label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppShadows.md,
      ),
      child: Text(label,
          style: AppTypography.labelLarge.copyWith(
              fontWeight: FontWeight.w700)),
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
    // Terminal orders never reach this sheet — OrderTrackingScreen redirects them
    // to the order details screen — so this only ever renders an in-flight order.
    final status = tracking.currentStatus;

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
          ...[
            _EtaHeadline(tracking: tracking, orderId: orderId),
            // The rider row (name, photo, CALL button) only means something once
            // someone is actually carrying the parcel. It used to appear from any
            // snapshotted agent name, so a customer could ring a rider about an
            // order still sitting on the packing bench.
            if (status.isDispatched && tracking.agentName != null) ...[
              AppSpacing.vGapMd,
              _PartnerRow(tracking: tracking),
            ],
            // The handover code, exactly when it matters: rider out, code still
            // spendable. Backend clears it after verification/lockout, so this
            // never shows a dead code.
            if (tracking.hasDeliveryOtp) ...[
              AppSpacing.vGapMd,
              DeliveryOtpCard(code: tracking.deliveryOtp),
            ],
            AppSpacing.vGapLg,
            Text(context.l10n.ordersOrderStatus, style: AppTypography.titleMedium),
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
class _EtaHeadline extends ConsumerWidget {
  const _EtaHeadline({required this.tracking, required this.orderId});

  final OrderTracking tracking;
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    final out = tracking.currentStatus == OrderStatus.outForDelivery;
    // Prefer the map's real road-route ETA; fall back to the backend's
    // straight-line estimate until (or unless) Directions answers.
    final routeEta = ref.watch(routeEtaProvider(orderId));
    final headline = out && routeEta != null && routeEta.isNotEmpty
        ? context.l10n.ordersArrivingIn(routeEta)
        : tracking.etaLabel ?? tracking.currentStatus.label;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                headline,
                style: AppTypography.headlineSmall,
              ),
              const SizedBox(height: 2),
              Text(
                out
                    ? context.l10n.ordersOnTheWayHeadline
                    : context.l10n.ordersWeWillUpdate,
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

/// Delivery partner row: rider photo + name + a real call action.
class _PartnerRow extends StatelessWidget {
  const _PartnerRow({required this.tracking});

  final OrderTracking tracking;

  Future<void> _call(BuildContext context) async {
    final phone = tracking.agentPhone;
    if (phone == null || phone.isEmpty) {
      // Should not happen — the button is hidden without a number — but stay safe.
      context.showSnack(context.l10n.ordersContactWhenAssigned);
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (context.mounted) {
      context.showSnack(context.l10n.ordersDialerError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final photo = tracking.agentPhotoUrl;
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
            // The rider's own photo when the backend has one; else the vehicle icon.
            foregroundImage: (photo != null && photo.isNotEmpty)
                ? NetworkImage(photo)
                : null,
            child: Icon(Icons.two_wheeler_rounded, color: vs.brand),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.ordersDeliveryPartner,
                    style: AppTypography.bodySmall
                        .copyWith(color: vs.textSecondary)),
                Text(tracking.agentName ?? context.l10n.ordersRiderOnTheWay,
                    style: AppTypography.titleMedium),
              ],
            ),
          ),
          // The call button only appears once the backend has the rider's number —
          // no dead control that pops a "not available" message.
          if (tracking.canCallAgent)
            IconButton.filledTonal(
              onPressed: () => _call(context),
              icon: const Icon(Icons.call_rounded),
            ),
        ],
      ),
    );
  }
}

/// Shown in the map area for an order whose address carries no coordinates, so we
/// never pin the map to a fabricated point.
/// What sits behind the sheet before a rider has the parcel — and after a
/// terminal outcome.
///
/// Replaces the live map for those states. Showing a map with a moving marker
/// for an order still being packed (or one that was cancelled) told the customer
/// something untrue: nothing was travelling anywhere.
class _PreDispatchBackdrop extends StatelessWidget {
  const _PreDispatchBackdrop({required this.status});

  final OrderStatus status;

  ({IconData icon, String text}) _content(BuildContext context) {
    if (status.isCompleted) {
      return (icon: Icons.check_circle_outline, text: status.label);
    }
    if (status.isFailed) {
      return (icon: Icons.cancel_outlined, text: status.label);
    }
    return (
      icon: Icons.inventory_2_outlined,
      text: context.l10n.ordersPreparingYourOrder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final c = _content(context);
    return Container(
      color: vs.brandTint.withValues(alpha: 0.3),
      alignment: Alignment.topCenter,
      padding: const EdgeInsets.only(top: 120, left: 32, right: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(c.icon, size: 48, color: vs.brand),
          AppSpacing.vGapMd,
          Text(
            c.text,
            textAlign: TextAlign.center,
            style: AppTypography.titleMedium.copyWith(color: vs.textSecondary),
          ),
        ],
      ),
    );
  }
}


class _MapUnavailable extends StatelessWidget {
  const _MapUnavailable();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      color: vs.brandTint.withValues(alpha: 0.3),
      alignment: Alignment.topCenter,
      padding: const EdgeInsets.only(top: 120, left: 32, right: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.map_outlined, size: 48, color: vs.textSecondary),
          AppSpacing.vGapMd,
          Text(
            context.l10n.ordersMapUnavailable,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
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
            Text(context.l10n.cartItemsCount(order.itemCount),
                style: AppTypography.titleMedium),
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
            child: Text(
                context.l10n.ordersMoreItems(order.items.length - items.length),
                style:
                    AppTypography.bodySmall.copyWith(color: vs.textSecondary)),
          ),
      ],
    );
  }
}


