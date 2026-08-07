import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/destination_map.dart';
import '../../../core/gps.dart';
import '../../../core/reason_screen.dart';
import '../../../core/ui.dart';
import '../../cash/cash_providers.dart';
import '../data/deliveries_data.dart';
import '../data/location_service.dart';
import 'deliveries_providers.dart';
import 'deliveries_screen.dart' show deliveryStatusColor, deliveryStatusLabel;
import 'active_delivery_map_screen.dart';
import 'delivery_success_screen.dart';

/// Drives a single delivery through the full production state machine:
///
///   assigned → accepted → picked_up → out_for_delivery → reached
///   → (otp verified) → (photo captured) → delivered
///
/// with one primary action per state, plus a "Report Failed" escape hatch from
/// any active state. Reads GET /deliveries/{id} and re-fetches after each
/// transition so the UI always reflects the backend's truth.
class DeliveryDetailScreen extends ConsumerStatefulWidget {
  const DeliveryDetailScreen({super.key, required this.id, this.orderCode = ''});

  /// Task id — the path segment for every state-machine call.
  final String id;

  /// Order code, shown in the app bar before the detail loads.
  final String orderCode;

  @override
  ConsumerState<DeliveryDetailScreen> createState() =>
      _DeliveryDetailScreenState();
}

/// Sentinel returned when an action was skipped because another one is already
/// in flight — not a success, so a caller's follow-on step doesn't run.
class _BusyRejected {
  const _BusyRejected._();
  static const instance = _BusyRejected._();
}

class _DeliveryDetailScreenState extends ConsumerState<DeliveryDetailScreen> {
  bool _busy = false;
  final _otpController = TextEditingController();
  final _picker = ImagePicker();

  // ~15s GPS breadcrumb posted while the task is out_for_delivery.
  Timer? _locationTimer;
  String? _trackingTaskId;

  @override
  void dispose() {
    _otpController.dispose();
    _locationTimer?.cancel();
    super.dispose();
  }

  DeliveriesRepo get _repo => ref.read(deliveriesRepoProvider);
  LocationService get _location => ref.read(locationServiceProvider);

  // ── error surfacing ──────────────────────────────────────────────────────
  /// Show a caught error: the backend envelope when there is one, otherwise a
  /// classified network/server message (so "no signal" never reads as a
  /// rejection).
  void _show(Object error) => showApiError(context, error);

  /// Run a repo call with the busy flag + refresh + error surfacing.
  ///
  /// Returns null on SUCCESS and the caught error otherwise — callers gate
  /// follow-on steps on `err == null`. It used to return `DeliveryApiException?`,
  /// which was null for a success AND for every non-API failure, so a dropped
  /// connection read as success: the app opened the live map on a trip that
  /// never started, and would have discarded an unsent proof photo.
  Future<Object?> _run(
    Future<AgentDelivery> Function() action, {
    String? successMsg,
  }) async {
    if (_busy) return _BusyRejected.instance;
    setState(() => _busy = true);
    try {
      final updated = await action();
      if (!mounted) return null;
      // Push the fresh record into both the detail + list providers.
      ref.invalidate(deliveryDetailProvider(widget.id));
      ref.invalidate(assignedDeliveriesProvider);
      _syncTracking(updated);
      if (successMsg != null) showToast(context, successMsg);
      return null;
    } catch (e) {
      if (mounted) _show(e);
      return e;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── location breadcrumb (only while out_for_delivery) ─────────────────────
  void _syncTracking(AgentDelivery d) {
    if (d.status == 'out_for_delivery') {
      _startTracking(d);
    } else {
      _stopTracking();
    }
  }

  void _startTracking(AgentDelivery d) {
    if (_trackingTaskId == d.id && _locationTimer != null) return;
    _stopTracking();
    _trackingTaskId = d.id;
    Future<void> ping() async {
      // Real fixes only: a breadcrumb is dispatch's picture of where this rider
      // actually is. Reporting the destination when GPS is off would tell
      // dispatch the rider is already at the door.
      final fix = await _location.current();
      if (fix == null) return; // No location source yet — degrade silently.
      await _repo.postLocation(
        taskId: d.id,
        latitude: fix.latitude,
        longitude: fix.longitude,
        accuracyM: fix.accuracyM,
      );
    }

    ping(); // immediate first ping
    _locationTimer =
        Timer.periodic(const Duration(seconds: 15), (_) => ping());
  }

  void _stopTracking() {
    _locationTimer?.cancel();
    _locationTimer = null;
    _trackingTaskId = null;
  }

  // ── state transitions ─────────────────────────────────────────────────────
  Future<void> _accept() => _run(() => _repo.accept(widget.id),
      successMsg: 'Delivery accepted');

  Future<void> _pickup() => _run(() => _repo.pickup(widget.id),
      successMsg: 'Picked up — ready to head out');

  Future<void> _outForDelivery() async {
    final err = await _run(
      () => _repo.outForDelivery(widget.id),
      successMsg: 'Out for delivery — OTP sent to customer',
    );
    // The trip has started — put the rider straight onto the live map, where
    // the route, the customer and the arrive action all live.
    if (err == null && mounted) _openLiveMap();
  }

  void _openLiveMap() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ActiveDeliveryMapScreen(
        taskId: widget.id,
        onArrive: () async {
          final d = ref.read(deliveryDetailProvider(widget.id)).valueOrNull;
          if (d != null) await _arrive(d);
        },
      ),
    ));
  }

  Future<void> _arrive(AgentDelivery d) async {
    // Arrival is the one check that the rider physically reached the customer,
    // and the backend can only check the coordinates this app sends. So it must
    // be a LIVE fix — never a cached one, and never the destination.
    if (_busy) return;
    // Hold the busy flag over the fix attempt too: it can take a few seconds,
    // and without it the button looks dead and invites a second tap.
    setState(() => _busy = true);
    GeoFix? fix;
    try {
      fix = await _location.currentLive();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    final live = fix;
    if (live == null) {
      if (!mounted) return;
      await promptEnableLocation(context);
      return;
    }
    await _run(
      () => _repo.arrive(widget.id,
          latitude: live.latitude, longitude: live.longitude),
      successMsg: "Arrival confirmed",
    );
    // 409 DELIVERY_LOCATION_MISMATCH (and any other failure) is surfaced by
    // _run via the envelope message.
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.isEmpty) {
      showToast(context, 'Enter the OTP shared with the customer', error: true);
      return;
    }
    final err = await _run(() => _repo.verifyOtp(widget.id, otp));
    if (err == null && mounted) {
      _otpController.clear();
      showToast(context, 'OTP verified');
    }
    // INVALID_DELIVERY_OTP (attempts-left) / MANUAL_VERIFICATION_REQUIRED
    // messages come straight from the envelope through _run.
  }

  /// A photo that was taken but hasn't reached the server yet. Kept in memory
  /// so a failed upload — the normal outcome at a doorway with one bar — can be
  /// retried instead of making the agent shoot the proof again (and explain to
  /// the customer why they're being photographed twice).
  Uint8List? _pendingPhotoBytes;
  double _pendingPhotoLat = 0;
  double _pendingPhotoLng = 0;

  bool get hasPendingPhoto => _pendingPhotoBytes != null;

  Future<void> _capturePhoto(AgentDelivery d) async {
    // Capture a real proof-of-delivery photo and attach it in ONE multipart
    // call (the backend's media engine stores it as a viewable private asset).
    //
    // Hardened: the picker used to run un-caught and `null` returned SILENTLY —
    // the agent shot a photo, Android reclaimed our activity (or the plugin
    // errored), and the tap just… did nothing, with no request ever leaving the
    // phone. Every exit now says something.
    XFile? shot;
    try {
      shot = await _picker.pickImage(
          source: ImageSource.camera, imageQuality: 70, maxWidth: 1600);
      if (shot == null) {
        // Android may have killed the activity during capture — recover it.
        final lost = await _picker.retrieveLostData();
        if (!lost.isEmpty) shot = lost.file;
      }
    } catch (_) {
      if (mounted) {
        showToast(context, "Couldn't open the camera. Try again.", error: true);
      }
      return;
    }
    if (shot == null) {
      if (mounted) {
        showToast(context, 'No photo received from the camera — try again.',
            error: true);
      }
      return;
    }
    final XFile photo = shot;

    // The photo's GPS stamp is evidence of where it was taken, so it must come
    // from the device — a live fix, or the last real one this phone produced.
    // It is never the delivery address, which is what the old fallback sent.
    final fix = await _location.current();
    if (fix == null) {
      if (!mounted) return;
      await promptEnableLocation(context);
      return;
    }

    final Uint8List bytes;
    try {
      bytes = await photo.readAsBytes();
    } catch (_) {
      if (mounted) {
        showToast(context, "Couldn't read the photo from the camera. Try again.",
            error: true);
      }
      return;
    }

    setState(() {
      _pendingPhotoBytes = bytes;
      _pendingPhotoLat = fix.latitude;
      _pendingPhotoLng = fix.longitude;
    });
    await _uploadPendingPhoto();
  }

  /// Send (or re-send) the captured proof photo. The bytes survive a failure so
  /// the agent can retry on better signal.
  Future<void> _uploadPendingPhoto() async {
    final bytes = _pendingPhotoBytes;
    if (bytes == null) return;
    final err = await _run(
      () => _repo.attachPhotoFile(widget.id,
          bytes: bytes,
          filename: 'pod_${widget.id}.jpg',
          latitude: _pendingPhotoLat,
          longitude: _pendingPhotoLng),
      successMsg: 'Proof photo attached',
    );
    if (err == null && mounted) {
      setState(() => _pendingPhotoBytes = null);
    }
  }


  Future<void> _complete() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final updated = await _repo.complete(widget.id);
      if (!mounted) return;
      ref.invalidate(deliveryDetailProvider(widget.id));
      ref.invalidate(assignedDeliveriesProvider);
      _syncTracking(updated);
      // Closing step → delivery success confirmation.
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DeliverySuccessScreen(delivery: updated),
      ));
    } catch (e) {
      if (mounted) _show(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _collectCash(AgentDelivery d) async {
    await _run(
      () async {
        final r = await _repo.collectCash(widget.id);
        // The dashboard In-Hand tile + Cash screen read the cash book — refresh
        // them so the new notes show immediately.
        ref.invalidate(cashSummaryProvider);
        if (mounted) {
          showToast(context,
              'Cash collected — ₹${r.cashInHand.toStringAsFixed(0)} now in hand');
        }
        return r.delivery;
      },
      successMsg: null,
    );
  }

  Future<void> _initiateReturn() => _run(
        () => _repo.initiateReturn(widget.id),
        successMsg: 'Return started — hand the items to the store',
      );

  Future<void> _reportFailed() async {
    final picked =
        await Navigator.of(context).push<({DeliveryFailReason value, String note})>(
      MaterialPageRoute(
        builder: (_) => ReasonScreen<DeliveryFailReason>(
          title: 'Report delivery failed',
          prompt: 'Why did the delivery fail?',
          submitLabel: 'Mark failed',
          danger: true,
          options: [
            for (final r in DeliveryFailReason.values) ReasonOption(r, r.label),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await _run(
      () => _repo.fail(widget.id, reason: picked.value, note: picked.note),
      successMsg: 'Delivery marked failed',
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(deliveryDetailProvider(widget.id));
    final title = widget.orderCode.isNotEmpty ? widget.orderCode : 'Delivery';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: async.when(
        loading: () => const Loading(),
        error: (_, __) => ErrorRetry(
          message: 'Could not load this delivery.',
          onRetry: () => ref.invalidate(deliveryDetailProvider(widget.id)),
        ),
        data: (delivery) {
          // Keep the GPS breadcrumb in step with the loaded status.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _syncTracking(delivery);
          });
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(deliveryDetailProvider(widget.id));
              await ref.read(deliveryDetailProvider(widget.id).future);
            },
            child: _DetailBody(
            delivery: delivery,
            busy: _busy,
            otpController: _otpController,
            hasDeviceGps: _location.hasDeviceGps,
            onAccept: _accept,
            onReject: _reportRejected,
            onPickup: _pickup,
            onOutForDelivery: _outForDelivery,
            onOpenMap: _openLiveMap,
            onArrive: () => _arrive(delivery),
            onVerifyOtp: _verifyOtp,
            onCapturePhoto: () => _capturePhoto(delivery),
            pendingPhotoUpload: hasPendingPhoto,
            onRetryPhotoUpload: _uploadPendingPhoto,
            onComplete: _complete,
            onCollectCash: () => _collectCash(delivery),
            onInitiateReturn: _initiateReturn,
            onReportFailed: _reportFailed,
            ),
          );
        },
      ),
    );
  }

  Future<void> _reportRejected() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject this delivery?'),
        content: TextField(
          controller: controller,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Reason',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AgentColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    final reason = controller.text.trim();
    controller.dispose();
    if (confirmed != true) return;
    await _run(
      () => _repo.reject(
          widget.id, reason.isEmpty ? 'Rejected by agent' : reason),
      successMsg: 'Delivery rejected',
    );
  }
}

/// The scrollable detail body: summary, customer, order, timeline + the
/// per-state action area.
Future<void> _dialNumber(BuildContext context, String phone) async {
  final uri = Uri(scheme: 'tel', path: phone);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  } else if (context.mounted) {
    showToast(context, 'Could not start a call to $phone', error: true);
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.delivery,
    required this.busy,
    required this.otpController,
    required this.hasDeviceGps,
    required this.onAccept,
    required this.onReject,
    required this.onPickup,
    required this.onOutForDelivery,
    required this.onOpenMap,
    required this.onArrive,
    required this.onVerifyOtp,
    required this.onCapturePhoto,
    required this.pendingPhotoUpload,
    required this.onRetryPhotoUpload,
    required this.onComplete,
    required this.onCollectCash,
    required this.onInitiateReturn,
    required this.onReportFailed,
  });

  final AgentDelivery delivery;
  final bool busy;
  final TextEditingController otpController;
  final bool hasDeviceGps;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onPickup;
  final VoidCallback onOutForDelivery;
  final VoidCallback onOpenMap;
  final VoidCallback onArrive;
  final VoidCallback onVerifyOtp;
  final VoidCallback onCapturePhoto;

  /// A proof photo is held on the device because its upload hasn't succeeded.
  final bool pendingPhotoUpload;
  final VoidCallback onRetryPhotoUpload;
  final VoidCallback onComplete;
  final VoidCallback onCollectCash;
  final VoidCallback onInitiateReturn;
  final VoidCallback onReportFailed;

  bool get _isTerminal =>
      delivery.status == 'delivered' ||
      delivery.status == 'cancelled' ||
      delivery.status == 'failed' ||
      delivery.status == 'rejected';

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _summaryCard(),
        const SizedBox(height: 12),
        _customerCard(),
        if (delivery.destLat != null && delivery.destLng != null) ...[
          const SizedBox(height: 12),
          DestinationMap(
            lat: delivery.destLat!,
            lng: delivery.destLng!,
            label: delivery.address.isNotEmpty ? delivery.address : 'Delivery location',
          ),
        ],
        const SizedBox(height: 12),
        _orderCard(),
        const SizedBox(height: 12),
        _timelineCard(),
        const SizedBox(height: 20),
        _ActionArea(
          delivery: delivery,
          busy: busy,
          otpController: otpController,
          hasDeviceGps: hasDeviceGps,
          onAccept: onAccept,
          onReject: onReject,
          onPickup: onPickup,
          onOutForDelivery: onOutForDelivery,
          onOpenMap: onOpenMap,
          onArrive: onArrive,
          onVerifyOtp: onVerifyOtp,
          onCapturePhoto: onCapturePhoto,
          pendingPhotoUpload: pendingPhotoUpload,
          onRetryPhotoUpload: onRetryPhotoUpload,
          onComplete: onComplete,
          onCollectCash: onCollectCash,
          onInitiateReturn: onInitiateReturn,
        ),
        if (!_isTerminal) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: busy ? null : onReportFailed,
            style: OutlinedButton.styleFrom(
              foregroundColor: AgentColors.danger,
              side: const BorderSide(color: AgentColors.danger),
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.report_gmailerrorred_outlined),
            label: const Text('Report Failed'),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _summaryCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LeadingIcon(
                  icon: Icons.local_shipping_rounded,
                  color: deliveryStatusColor(delivery.status),
                  size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  delivery.orderCode.isNotEmpty ? delivery.orderCode : 'Order',
                  style:
                      const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                ),
              ),
              StatusPill(
                label: deliveryStatusLabel(delivery.status),
                color: deliveryStatusColor(delivery.status),
              ),
            ],
          ),
          if (delivery.attemptNo > 0) ...[
            const SizedBox(height: 6),
            Text('Attempt #${delivery.attemptNo}',
                style: const TextStyle(color: AgentColors.textSecondary)),
          ],
          if (delivery.status == 'delivered' && delivery.earnings > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AgentColors.green.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      color: AgentColors.green, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Delivered • You earned ₹${delivery.earnings.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: AgentColors.green, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
          if (delivery.failureReason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Reason: ${delivery.failureReason}',
                style: const TextStyle(color: AgentColors.danger)),
          ],
        ],
      ),
    );
  }

  Widget _customerCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Customer',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AgentColors.textSecondary)),
          const SizedBox(height: 8),
          _row(Icons.person_outline,
              delivery.customerName.isNotEmpty ? delivery.customerName : '—'),
          if (delivery.customerPhone.isNotEmpty) ...[
            const SizedBox(height: 8),
            Builder(
              builder: (ctx) => InkWell(
                onTap: () => _dialNumber(ctx, delivery.customerPhone),
                child: Row(
                  children: [
                    const Icon(Icons.phone_outlined,
                        size: 18, color: AgentColors.brand),
                    const SizedBox(width: 8),
                    Text(delivery.customerPhone,
                        style: const TextStyle(
                            color: AgentColors.brand,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          _row(Icons.location_on_outlined,
              delivery.address.isNotEmpty ? delivery.address : '—'),
          if (delivery.distanceKm > 0) ...[
            const SizedBox(height: 8),
            _row(Icons.straighten_outlined,
                '${delivery.distanceKm.toStringAsFixed(1)} km away'),
          ],
        ],
      ),
    );
  }

  Widget _orderCard() {
    final method = delivery.paymentMethod.toLowerCase();
    final isCredit = method.contains('credit');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Order',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AgentColors.textSecondary)),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('₹${delivery.amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 18)),
              const SizedBox(width: 10),
              if (delivery.paymentMethod.isNotEmpty)
                _paymentBadge(
                  isCredit ? 'VS CREDIT' : delivery.paymentMethod.toUpperCase(),
                  isCredit ? AgentColors.brand : AgentColors.amber,
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (delivery.itemCount > 0)
            _kv('Items', delivery.itemCount.toString()),
          if (delivery.paymentStatus.isNotEmpty)
            _kv('Payment status', deliveryStatusLabel(delivery.paymentStatus)),
        ],
      ),
    );
  }

  Widget _paymentBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }

  /// Vertical stepper/timeline of the state machine with the current position
  /// highlighted.
  Widget _timelineCard() {
    const steps = [
      ('assigned', 'Assigned'),
      ('accepted', 'Accepted'),
      ('picked_up', 'Picked Up'),
      ('out_for_delivery', 'Out for Delivery'),
      ('reached', 'Reached'),
      ('delivered', 'Delivered'),
    ];
    final order = {for (var i = 0; i < steps.length; i++) steps[i].$1: i};
    final currentIdx = order[delivery.status] ?? -1;
    final failed = delivery.status == 'failed' ||
        delivery.status == 'rejected' ||
        delivery.status == 'cancelled';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Progress',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AgentColors.textSecondary)),
          const SizedBox(height: 12),
          for (var i = 0; i < steps.length; i++)
            _timelineRow(
              label: steps[i].$2,
              done: !failed && currentIdx > i,
              active: !failed && currentIdx == i,
              isLast: i == steps.length - 1,
            ),
          if (failed) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.cancel, color: AgentColors.danger, size: 20),
                const SizedBox(width: 10),
                Text(deliveryStatusLabel(delivery.status),
                    style: const TextStyle(
                        color: AgentColors.danger,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _timelineRow({
    required String label,
    required bool done,
    required bool active,
    required bool isLast,
  }) {
    final color = done
        ? AgentColors.green
        : active
            ? AgentColors.brand
            : AgentColors.border;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: (done || active) ? color : Colors.transparent,
                  border: Border.all(color: color, width: 2),
                  shape: BoxShape.circle,
                ),
                child: done
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : active
                        ? const Center(
                            child: Icon(Icons.circle,
                                size: 8, color: Colors.white))
                        : null,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: done ? AgentColors.green : AgentColors.border,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 14, top: 1),
            child: Text(
              label,
              style: TextStyle(
                fontWeight:
                    active ? FontWeight.w700 : FontWeight.w500,
                color: (done || active)
                    ? Colors.black87
                    : AgentColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AgentColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child:
                Text(k, style: const TextStyle(color: AgentColors.textSecondary)),
          ),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// The single-primary-action area, switched on the task status.
class _ActionArea extends StatelessWidget {
  const _ActionArea({
    required this.delivery,
    required this.busy,
    required this.otpController,
    required this.hasDeviceGps,
    required this.onAccept,
    required this.onReject,
    required this.onPickup,
    required this.onOutForDelivery,
    required this.onOpenMap,
    required this.onArrive,
    required this.onVerifyOtp,
    required this.onCapturePhoto,
    required this.pendingPhotoUpload,
    required this.onRetryPhotoUpload,
    required this.onComplete,
    required this.onCollectCash,
    required this.onInitiateReturn,
  });

  final AgentDelivery delivery;
  final bool busy;
  final TextEditingController otpController;
  final bool hasDeviceGps;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onPickup;
  final VoidCallback onOutForDelivery;
  final VoidCallback onOpenMap;
  final VoidCallback onArrive;
  final VoidCallback onVerifyOtp;
  final VoidCallback onCapturePhoto;
  final bool pendingPhotoUpload;
  final VoidCallback onRetryPhotoUpload;
  final VoidCallback onComplete;
  final VoidCallback onCollectCash;
  final VoidCallback onInitiateReturn;

  @override
  Widget build(BuildContext context) {
    switch (delivery.status) {
      case 'assigned':
        return Column(
          children: [
            _primary(
              label: 'Accept',
              icon: Icons.check_circle_outline,
              onPressed: onAccept,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: busy ? null : onReject,
              style: OutlinedButton.styleFrom(
                foregroundColor: AgentColors.danger,
                side: const BorderSide(color: AgentColors.danger),
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Reject'),
            ),
          ],
        );

      case 'accepted':
        return _primary(
          label: 'Start Pickup',
          icon: Icons.inventory_2_outlined,
          onPressed: onPickup,
        );

      case 'picked_up':
        return _primary(
          label: 'Out for Delivery',
          icon: Icons.local_shipping_outlined,
          onPressed: onOutForDelivery,
        );

      case 'out_for_delivery':
        return Column(
          children: [
            if (!hasDeviceGps) _gpsNote(),
            // The trip's home is the full-screen live map (route, follow camera,
            // customer card); the actions here stay as a fallback.
            OutlinedButton.icon(
              onPressed: busy ? null : onOpenMap,
              icon: const Icon(Icons.map_outlined),
              label: const Text('Open Live Map'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 12),
            _primary(
              label: "I've Arrived",
              icon: Icons.where_to_vote_outlined,
              onPressed: onArrive,
            ),
          ],
        );

      case 'reached':
        return _reachedActions(context);

      case 'delivered':
        // COD: the handover isn't finished until the cash is confirmed — that's
        // what marks the order PAID and puts the notes into the agent's in-hand.
        if (delivery.paymentMethod == 'cod' &&
            delivery.paymentStatus != 'paid') {
          return Column(
            children: [
              _primary(
                label:
                    'Collect ₹${delivery.amount.toStringAsFixed(0)} cash',
                icon: Icons.payments_outlined,
                onPressed: onCollectCash,
              ),
              const SizedBox(height: 8),
              const Text(
                'Confirm once the customer has paid — this marks the order paid '
                'and adds the amount to your cash in hand.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
            ],
          );
        }
        return _doneNote('Delivered. Thanks!');
      case 'failed':
        return Column(
          children: [
            _doneNote('This delivery was marked failed — attempt recorded.'),
            const SizedBox(height: 12),
            _primary(
              label: 'Return items to store',
              icon: Icons.assignment_return_outlined,
              onPressed: onInitiateReturn,
            ),
          ],
        );
      case 'return_initiated':
        return _doneNote(
            'Heading back — hand the items to the store; they confirm receipt.');
      case 'rejected':
        return _doneNote('You rejected this delivery.');
      case 'cancelled':
        return _doneNote('This order was cancelled.');
      default:
        // A status this build doesn't know (backend added one, or the task is
        // in a transient state). Say so instead of rendering an empty area that
        // looks like a broken screen with no way forward.
        return _doneNote(
            'This delivery is "${deliveryStatusLabel(delivery.status)}". '
            'Pull down to refresh, or contact the store if it stays here.');
    }
  }

  /// At `reached`: OTP entry → photo → complete, gated in order.
  Widget _reachedActions(BuildContext context) {
    if (delivery.manualVerificationRequired) {
      return AppCard(
        child: Row(
          children: [
            const Icon(Icons.support_agent, color: AgentColors.amber),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'OTP attempts exhausted. Contact store for manual verification.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    if (!delivery.otpVerified) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Enter delivery OTP',
              style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: otpController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              hintText: 'Enter the OTP shared with the customer',
              counterText: '',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.password_outlined),
            ),
          ),
          const SizedBox(height: 12),
          _primary(
            label: 'Verify OTP',
            icon: Icons.verified_outlined,
            onPressed: onVerifyOtp,
          ),
        ],
      );
    }

    if (!delivery.hasPhoto) {
      return Column(
        children: [
          AppCard(
            child: Row(
              children: const [
                Icon(Icons.verified, color: AgentColors.green, size: 18),
                SizedBox(width: 8),
                Text('OTP verified',
                    style: TextStyle(
                        color: AgentColors.green, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (pendingPhotoUpload) ...[
            // The photo exists on the phone; only the upload failed. Offer the
            // retry rather than sending the agent back to the camera.
            AppCard(
              child: Row(
                children: const [
                  Icon(Icons.cloud_upload_outlined,
                      color: AgentColors.amber, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Photo saved on your phone — it hasn't reached VS Mart yet.",
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _primary(
              label: 'Retry upload',
              icon: Icons.refresh,
              onPressed: onRetryPhotoUpload,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onCapturePhoto,
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              label: const Text('Take a new photo instead'),
            ),
          ] else
            _primary(
              label: 'Capture Photo (required)',
              icon: Icons.photo_camera_outlined,
              onPressed: onCapturePhoto,
            ),
        ],
      );
    }

    // OTP + photo done → complete.
    return Column(
      children: [
        AppCard(
          child: Row(
            children: const [
              Icon(Icons.verified, color: AgentColors.green, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text('OTP verified • Proof attached',
                    style: TextStyle(
                        color: AgentColors.green,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _primary(
          label: 'Complete Delivery',
          icon: Icons.check_circle,
          color: AgentColors.green,
          onPressed: onComplete,
        ),
      ],
    );
  }

  Widget _primary({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return FilledButton.icon(
      onPressed: busy ? null : onPressed,
      style: color != null
          ? FilledButton.styleFrom(backgroundColor: color)
          : null,
      icon: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
          : Icon(icon),
      label: Text(label),
    );
  }

  Widget _gpsNote() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Row(
          children: const [
            Icon(Icons.location_off_outlined,
                color: AgentColors.amber, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Live GPS unavailable in this build — arrival uses the '
                'destination location.',
                style: TextStyle(color: AgentColors.textSecondary, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _doneNote(String text) {
    return Center(
      child: Text(text,
          style: const TextStyle(color: AgentColors.textSecondary)),
    );
  }
}
