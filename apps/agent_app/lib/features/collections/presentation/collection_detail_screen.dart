import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/destination_map.dart';
import '../../../core/reason_screen.dart';
import '../../../core/ui.dart';
import '../collections_providers.dart';
import '../data/collections_data.dart';
import 'collection_receipt_screen.dart';
import 'collections_screen.dart'
    show collectionStatusColor, collectionStatusLabel;

// Strict INR formatting (exact paise, Indian grouping, 2 decimals).
String _money(double v) => agentMoney(v);

/// Drives a single collection through the full production state machine:
///
///   requested/assigned → accepted → en_route → reached
///   → (otp verified) → (collect) → collected
///
/// with one primary action per state, plus "Report Failed" and "Raise Dispute"
/// escape hatches from any active state. Reads GET /collections/{id} and
/// re-fetches after each transition so the UI always reflects the backend.
class CollectionDetailScreen extends ConsumerStatefulWidget {
  const CollectionDetailScreen({
    super.key,
    required this.id,
    this.customerName = '',
  });

  /// Task id — the path segment for every state-machine call.
  final String id;

  /// Customer name, shown in the app bar before the detail loads.
  final String customerName;

  @override
  ConsumerState<CollectionDetailScreen> createState() =>
      _CollectionDetailScreenState();
}

/// Sentinel returned when an action was skipped because another one is already
/// in flight — not a success, so a caller's follow-on step doesn't run.
class _BusyRejected {
  const _BusyRejected._();
  static const instance = _BusyRejected._();
}

class _CollectionDetailScreenState
    extends ConsumerState<CollectionDetailScreen> {
  bool _busy = false;
  final _otpController = TextEditingController();
  final _amountController = TextEditingController();

  // Keeps the amount field from being overwritten on every rebuild once the
  // agent has started editing it.
  bool _amountSeeded = false;

  @override
  void dispose() {
    _otpController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  CollectionsRepo get _repo => ref.read(collectionsRepoProvider);

  // ── error surfacing ──────────────────────────────────────────────────────
  /// Show a caught error: the backend envelope when there is one, otherwise a
  /// classified network/server message.
  void _show(Object error) => showApiError(context, error);

  /// Run a repo call with the busy flag + refresh + error surfacing.
  ///
  /// Returns null on SUCCESS and the caught error otherwise. It used to return
  /// `CollectionApiException?`, which was null for a success AND for every
  /// non-API failure — so on a dropped connection the agent was told "OTP sent
  /// to the customer to confirm ₹X" for a request that never left the phone,
  /// and "OTP verified" (with the field cleared) for a verification that never
  /// happened. On a cash-recovery flow those are the two worst things to lie
  /// about.
  Future<Object?> _run(
    Future<AgentCollection> Function() action, {
    String? successMsg,
  }) async {
    if (_busy) return _BusyRejected.instance;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return null;
      // Push the fresh record into both the detail + list providers.
      ref.invalidate(collectionDetailProvider(widget.id));
      ref.invalidate(assignedCollectionsProvider);
      if (successMsg != null) showToast(context, successMsg);
      return null;
    } catch (e) {
      if (mounted) _show(e);
      return e;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── state transitions ─────────────────────────────────────────────────────
  Future<void> _accept() =>
      _run(() => _repo.accept(widget.id), successMsg: 'Collection accepted');

  Future<void> _enRoute() => _run(() => _repo.enRoute(widget.id),
      successMsg: 'On your way — heading to the customer');

  Future<void> _reach() => _run(() => _repo.reach(widget.id),
      successMsg: 'Arrival confirmed');

  /// Agent enters the amount → send the customer an alert to confirm exactly that
  /// figure and share the OTP. Validated in integer paise.
  Future<void> _requestOtp(AgentCollection c) async {
    final dueCents = (c.amountDue * 100).round();
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      showToast(context, 'Enter a valid amount to collect', error: true);
      return;
    }
    final exact = amount * 100;
    if ((exact - exact.roundToDouble()).abs() > 1e-6) {
      showToast(context, 'Amount can have at most 2 decimal places.',
          error: true);
      return;
    }
    if (dueCents > 0 && exact.round() > dueCents) {
      showToast(context, 'Amount cannot exceed the ${_money(c.amountDue)} due.',
          error: true);
      return;
    }
    final err = await _run(() => _repo.requestOtp(widget.id, amount));
    if (err == null && mounted) {
      showToast(context,
          'OTP sent to the customer to confirm ${_money(amount)}.');
    }
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
    // INVALID_COLLECTION_OTP (attempts-left) / COLLECTION_OTP_LOCKED messages
    // come straight from the envelope through _run.
  }

  Future<void> _collect(AgentCollection c) async {
    if (_busy) return;
    // The amount was confirmed by the customer via the OTP — the backend settles
    // exactly that figure, so we send no amount here.
    final confirmed = c.otpAmount;
    setState(() => _busy = true);
    try {
      final result = await _repo.collect(widget.id);
      if (!mounted) return;
      _amountController.clear();
      ref.invalidate(collectionDetailProvider(widget.id));
      ref.invalidate(assignedCollectionsProvider);
      if (result.partial) {
        showToast(
          context,
          'Recorded ${_money(confirmed)}. ${_money(result.collection.amountDue)} '
          'still due — request a new OTP for the balance.',
        );
      } else {
        // Full recovery → show the digital receipt as the closing step.
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CollectionReceiptScreen(
            collection: result.collection,
            collectedAmount:
                confirmed > 0 ? confirmed : result.collection.collectedAmount,
          ),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      _show(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _raiseDispute() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Raise a dispute'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Note',
            hintText: 'Describe the disagreement or issue',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AgentColors.amber),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Raise Dispute'),
          ),
        ],
      ),
    );
    final note = controller.text.trim();
    controller.dispose();
    if (confirmed != true) return;
    if (note.isEmpty) {
      if (mounted) showToast(context, 'A dispute note is required', error: true);
      return;
    }
    await _run(
      () => _repo.dispute(widget.id, note),
      successMsg: 'Dispute raised',
    );
  }

  Future<void> _reportFailed() async {
    final picked = await Navigator.of(context)
        .push<({CollectionFailReason value, String note})>(
      MaterialPageRoute(
        builder: (_) => ReasonScreen<CollectionFailReason>(
          title: 'Report collection failed',
          prompt: 'Why could the payment not be collected?',
          submitLabel: 'Mark failed',
          danger: true,
          options: [
            for (final r in CollectionFailReason.values) ReasonOption(r, r.label),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await _run(
      () => _repo.fail(widget.id, reason: picked.value, note: picked.note),
      successMsg: 'Collection marked failed',
    );
  }

  Future<void> _reportRejected() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject this collection?'),
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
      successMsg: 'Collection rejected',
    );
  }

  /// Seed the amount field with the outstanding due the first time we land on
  /// the verified state, so the default is a full collection.
  void _seedAmount(AgentCollection c) {
    if (_amountSeeded) return;
    // Seed the amount field (default = full due) when the agent lands on the
    // "reached" step, before requesting the amount-bound OTP.
    if (c.status == 'reached' && !c.otpVerified && !c.otpPending) {
      final due = c.amountDue;
      if (due > 0) {
        _amountController.text = due == due.roundToDouble()
            ? due.toStringAsFixed(0)
            : due.toStringAsFixed(2);
      }
      _amountSeeded = true;
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(collectionDetailProvider(widget.id));
    final title =
        widget.customerName.isNotEmpty ? widget.customerName : 'Collection';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: async.when(
        loading: () => const Loading(),
        error: (_, __) => ErrorRetry(
          message: 'Could not load this collection.',
          onRetry: () => ref.invalidate(collectionDetailProvider(widget.id)),
        ),
        data: (collection) {
          _seedAmount(collection);
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(collectionDetailProvider(widget.id));
              await ref.read(collectionDetailProvider(widget.id).future);
            },
            child: _DetailBody(
            collection: collection,
            busy: _busy,
            otpController: _otpController,
            amountController: _amountController,
            onAccept: _accept,
            onReject: _reportRejected,
            onEnRoute: _enRoute,
            onReach: _reach,
            onRequestOtp: () => _requestOtp(collection),
            onVerifyOtp: _verifyOtp,
            onCollect: () => _collect(collection),
            onReportFailed: _reportFailed,
            onRaiseDispute: _raiseDispute,
            ),
          );
        },
      ),
    );
  }
}

Future<void> _dialNumber(BuildContext context, String phone) async {
  final uri = Uri(scheme: 'tel', path: phone);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  } else if (context.mounted) {
    showToast(context, 'Could not start a call to $phone', error: true);
  }
}

/// The scrollable detail body: summary, customer, recovery amounts, timeline +
/// the per-state action area.
class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.collection,
    required this.busy,
    required this.otpController,
    required this.amountController,
    required this.onAccept,
    required this.onReject,
    required this.onEnRoute,
    required this.onReach,
    required this.onRequestOtp,
    required this.onVerifyOtp,
    required this.onCollect,
    required this.onReportFailed,
    required this.onRaiseDispute,
  });

  final AgentCollection collection;
  final bool busy;
  final TextEditingController otpController;
  final TextEditingController amountController;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onEnRoute;
  final VoidCallback onReach;
  final VoidCallback onRequestOtp;
  final VoidCallback onVerifyOtp;
  final VoidCallback onCollect;
  final VoidCallback onReportFailed;
  final VoidCallback onRaiseDispute;

  bool get _isTerminal =>
      collection.status == 'collected' ||
      collection.status == 'cancelled' ||
      collection.status == 'failed' ||
      collection.status == 'rejected' ||
      collection.status == 'disputed';

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _summaryCard(),
        const SizedBox(height: 12),
        _customerCard(),
        if (collection.hasLocation) ...[
          const SizedBox(height: 12),
          DestinationMap(
            lat: collection.customerLat!,
            lng: collection.customerLng!,
            label: collection.address.isNotEmpty ? collection.address : 'Customer location',
          ),
        ],
        const SizedBox(height: 12),
        _amountsCard(),
        const SizedBox(height: 12),
        _timelineCard(),
        const SizedBox(height: 20),
        _ActionArea(
          collection: collection,
          busy: busy,
          otpController: otpController,
          amountController: amountController,
          onAccept: onAccept,
          onReject: onReject,
          onEnRoute: onEnRoute,
          onReach: onReach,
          onRequestOtp: onRequestOtp,
          onVerifyOtp: onVerifyOtp,
          onCollect: onCollect,
        ),
        if (!_isTerminal) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: busy ? null : onRaiseDispute,
            style: OutlinedButton.styleFrom(
              foregroundColor: AgentColors.amber,
              side: const BorderSide(color: AgentColors.amber),
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.gavel_outlined),
            label: const Text('Raise Dispute'),
          ),
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
                  icon: Icons.account_balance_wallet_rounded,
                  color: collectionStatusColor(collection.status),
                  size: 44),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Cash Recovery',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                ),
              ),
              StatusPill(
                label: collectionStatusLabel(collection.status),
                color: collectionStatusColor(collection.status),
              ),
            ],
          ),
          if (collection.isPriority || collection.escalated) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (collection.isPriority)
                  _badge('PRIORITY', Icons.priority_high_rounded,
                      AgentColors.amber),
                if (collection.isPriority && collection.escalated)
                  const SizedBox(width: 8),
                if (collection.escalated)
                  _badge('ESCALATED', Icons.trending_up_rounded,
                      AgentColors.danger),
              ],
            ),
          ],
          if (collection.attemptNo > 0) ...[
            const SizedBox(height: 8),
            Text('Attempt #${collection.attemptNo}',
                style: const TextStyle(color: AgentColors.textSecondary)),
          ],
          if (collection.status == 'collected') ...[
            const SizedBox(height: 10),
            _banner(
              color: AgentColors.green,
              icon: Icons.check_circle,
              text:
                  'Collected • ${_money(collection.collectedAmount > 0 ? collection.collectedAmount : collection.amount)} recovered',
            ),
          ],
          if (collection.status == 'partially_collected') ...[
            const SizedBox(height: 10),
            _banner(
              color: AgentColors.amber,
              icon: Icons.payments_outlined,
              text:
                  'Partially collected • ${_money(collection.amountDue)} still due',
            ),
          ],
          if (collection.failureReason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Reason: ${collection.failureReason}',
                style: const TextStyle(color: AgentColors.danger)),
          ],
        ],
      ),
    );
  }

  Widget _banner(
      {required Color color, required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style:
                    TextStyle(color: color, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _badge(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w800)),
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
              collection.customerName.isNotEmpty ? collection.customerName : '—'),
          if (collection.customerPhone.isNotEmpty) ...[
            const SizedBox(height: 8),
            Builder(
              builder: (ctx) => InkWell(
                onTap: () => _dialNumber(ctx, collection.customerPhone),
                child: Row(
                  children: [
                    const Icon(Icons.phone_outlined,
                        size: 18, color: AgentColors.brand),
                    const SizedBox(width: 8),
                    Text(collection.customerPhone,
                        style: const TextStyle(
                            color: AgentColors.brand,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    const Text('Tap to call',
                        style: TextStyle(
                            color: AgentColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _amountsCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recovery',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AgentColors.textSecondary)),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(_money(collection.amount),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 22)),
              const SizedBox(width: 8),
              const Text('to recover',
                  style: TextStyle(color: AgentColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 10),
          _kv('Collected so far', _money(collection.collectedAmount),
              color: collection.collectedAmount > 0 ? AgentColors.green : null),
          _kv('Remaining due', _money(collection.amountDue),
              color: collection.amountDue > 0 ? AgentColors.brand : null),
        ],
      ),
    );
  }

  /// Vertical stepper/timeline of the state machine with the current position
  /// highlighted.
  Widget _timelineCard() {
    const steps = [
      ('assigned', 'Assigned'),
      ('accepted', 'Accepted'),
      ('en_route', 'En Route'),
      ('reached', 'Reached'),
      ('collected', 'Collected'),
    ];
    // `requested` shares the first step with `assigned`.
    final order = {for (var i = 0; i < steps.length; i++) steps[i].$1: i};
    var currentIdx = order[collection.status] ?? -1;
    if (collection.status == 'requested') currentIdx = 0;
    if (collection.status == 'partially_collected') {
      currentIdx = order['collected'] ?? steps.length - 1;
    }
    final failed = collection.status == 'failed' ||
        collection.status == 'rejected' ||
        collection.status == 'cancelled' ||
        collection.status == 'disputed';

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
                Text(collectionStatusLabel(collection.status),
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
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
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

  Widget _kv(String k, String v, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(k,
                style: const TextStyle(color: AgentColors.textSecondary)),
          ),
          Text(v,
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: color ?? Colors.black87)),
        ],
      ),
    );
  }
}

/// The single-primary-action area, switched on the task status.
class _ActionArea extends StatelessWidget {
  const _ActionArea({
    required this.collection,
    required this.busy,
    required this.otpController,
    required this.amountController,
    required this.onAccept,
    required this.onReject,
    required this.onEnRoute,
    required this.onReach,
    required this.onRequestOtp,
    required this.onVerifyOtp,
    required this.onCollect,
  });

  final AgentCollection collection;
  final bool busy;
  final TextEditingController otpController;
  final TextEditingController amountController;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onEnRoute;
  final VoidCallback onReach;
  final VoidCallback onRequestOtp;
  final VoidCallback onVerifyOtp;
  final VoidCallback onCollect;

  @override
  Widget build(BuildContext context) {
    switch (collection.status) {
      case 'requested':
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
          label: 'On My Way',
          icon: Icons.directions_run_outlined,
          onPressed: onEnRoute,
        );

      case 'en_route':
        return _primary(
          label: "I've Arrived",
          icon: Icons.where_to_vote_outlined,
          onPressed: onReach,
        );

      case 'reached':
        return _reachedActions(context);

      case 'collected':
        return _doneNote('Cash collected. Recovery complete.');
      case 'partially_collected':
        return _partialActions(context);
      case 'failed':
        return _doneNote('This collection was marked failed.');
      case 'rejected':
        return _doneNote('You rejected this collection.');
      case 'cancelled':
        return _doneNote('This collection was cancelled.');
      case 'disputed':
        return _doneNote('This collection is under dispute.');
      default:
        return const SizedBox.shrink();
    }
  }

  /// At `reached`: OTP entry → cash collection, gated in order.
  /// The amount-bound OTP flow at `reached`:
  ///   enter amount → send OTP → customer confirms → verify → collect.
  Widget _reachedActions(BuildContext context) {
    if (collection.manualVerificationRequired && !collection.otpVerified) {
      return AppCard(
        child: Row(
          children: const [
            Icon(Icons.support_agent, color: AgentColors.amber),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Supervisor verification required. Contact your supervisor '
                'to verify this collection.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }
    if (collection.otpVerified) return _confirmCollect(context);
    if (collection.otpPending) return _confirmOtp(context);
    return _amountEntry(context);
  }

  /// After a partial, the balance is recovered via a fresh amount-bound OTP.
  Widget _partialActions(BuildContext context) {
    if (collection.amountDue <= 0) return _doneNote('Fully collected.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Row(
            children: [
              const Icon(Icons.payments_outlined,
                  color: AgentColors.amber, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Partially collected • ${_money(collection.amountDue)} still due',
                  style: const TextStyle(
                      color: AgentColors.amber, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (collection.otpVerified)
          _confirmCollect(context)
        else if (collection.otpPending)
          _confirmOtp(context)
        else
          _amountEntry(context),
      ],
    );
  }

  // ── phase 1: agent enters the amount → send OTP to the customer ──
  Widget _amountEntry(BuildContext context) {
    final due = collection.amountDue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('How much are you collecting?',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        TextField(
          controller: amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: InputDecoration(
            prefixText: '₹ ',
            helperText: due > 0 ? 'Amount due is ${_money(due)}.' : null,
            prefixIcon: const Icon(Icons.currency_rupee),
          ),
        ),
        const SizedBox(height: 12),
        _primary(
          label: 'Send OTP to customer',
          icon: Icons.sms_outlined,
          onPressed: onRequestOtp,
        ),
      ],
    );
  }

  // ── phase 2: customer confirms the amount → agent enters the code ──
  Widget _confirmOtp(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Row(
            children: [
              const Icon(Icons.mark_email_read_outlined,
                  color: AgentColors.brand, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'OTP sent to the customer to confirm '
                  '${_money(collection.otpAmount)}. Ask them to check the amount '
                  'and read out the code.',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text('Enter confirmation OTP',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        TextField(
          controller: otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            hintText: 'OTP shared by the customer',
            counterText: '',
            prefixIcon: Icon(Icons.password_outlined),
          ),
        ),
        const SizedBox(height: 12),
        _primary(
          label: 'Verify & confirm',
          icon: Icons.verified_outlined,
          onPressed: onVerifyOtp,
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: busy ? null : onRequestOtp,
          child: const Text('Change amount / resend OTP'),
        ),
      ],
    );
  }

  // ── phase 3: OTP verified → collect the confirmed amount ──
  Widget _confirmCollect(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Row(
            children: [
              const Icon(Icons.verified, color: AgentColors.green, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Customer confirmed ${_money(collection.otpAmount)}',
                  style: const TextStyle(
                      color: AgentColors.green, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _primary(
          label: 'Collect ${_money(collection.otpAmount)}',
          icon: Icons.payments,
          color: AgentColors.green,
          onPressed: onCollect,
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

  Widget _doneNote(String text) {
    return Center(
      child: Text(text,
          style: const TextStyle(color: AgentColors.textSecondary)),
    );
  }
}
