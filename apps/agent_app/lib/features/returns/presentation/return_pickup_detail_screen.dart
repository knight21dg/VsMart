import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api_exception.dart';
import '../../../core/ui.dart';
import '../data/returns_data.dart';
import '../returns_providers.dart';
import 'return_photo_view.dart';
import 'return_pickups_screen.dart';

/// The doorstep flow for one return pickup.
///
/// accept → en route → reached → capture condition photo → ACCEPT or REJECT.
/// The agent decides at the customer's door; accepting only records that the
/// goods are collected and the condition checks out. No money moves here — the
/// store processes the refund afterwards.
class ReturnPickupDetailScreen extends ConsumerStatefulWidget {
  const ReturnPickupDetailScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<ReturnPickupDetailScreen> createState() =>
      _ReturnPickupDetailScreenState();
}

class _ReturnPickupDetailScreenState
    extends ConsumerState<ReturnPickupDetailScreen> {
  final _picker = ImagePicker();
  bool _busy = false;

  /// Line id → accepted quantity. Only lines the agent actually changed are
  /// sent; anything untouched settles at the full requested quantity.
  final Map<String, int> _decisions = {};

  ReturnsRepo get _repo => ref.read(returnsRepoProvider);

  void _refresh() {
    ref.invalidate(returnPickupDetailProvider(widget.id));
    ref.invalidate(assignedReturnPickupsProvider);
  }

  /// Run a repo call with a busy guard, surfacing the backend envelope's own
  /// message rather than a generic failure.
  Future<bool> _run(Future<ReturnPickup> Function() action,
      {required String successMsg}) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return true;
      _refresh();
      showToast(context, successMsg);
      return true;
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.display, error: true);
      return false;
    } catch (e) {
      if (mounted) showToast(context, 'Something went wrong: $e', error: true);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _capturePhoto(ReturnPickup p) async {
    XFile? shot;
    try {
      shot = await _picker.pickImage(
          source: ImageSource.camera, imageQuality: 70, maxWidth: 1600);
      if (shot == null) {
        // Android may have killed the activity mid-capture — recover it.
        final lost = await _picker.retrieveLostData();
        if (!lost.isEmpty) shot = lost.file;
      }
    } catch (e) {
      if (mounted) showToast(context, 'Camera failed: $e', error: true);
      return;
    }
    if (shot == null) {
      if (mounted) {
        showToast(context, 'No photo received from the camera — try again.',
            error: true);
      }
      return;
    }
    final photo = shot;
    await _run(
      () async => _repo.uploadPhoto(
        widget.id,
        await photo.readAsBytes(),
        filename: 'return_${widget.id}.jpg',
        lat: p.destLat,
        lng: p.destLng,
      ),
      successMsg: 'Condition photo attached',
    );
  }

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(uri) && mounted) {
      showToast(context, 'Could not open the dialler', error: true);
    }
  }

  // ── settle at the door ──
  Future<void> _accept(ReturnPickup p) async {
    final partial = _decisions.entries
        .where((e) => e.value != _requestedQty(p, e.key))
        .isNotEmpty;
    final refund = _projectedRefund(p);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(partial ? 'Accept part of this return?' : 'Accept return?'),
        content: Text(
          partial
              ? 'You are accepting fewer items than the customer requested. '
                  'Their refund becomes ${agentMoney(refund)}.\n\n'
                  'Collect the goods before confirming.'
              : 'Confirm the goods are collected and in acceptable condition. '
                  'The customer is refunded ${agentMoney(refund)} by the store.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Accept')),
        ],
      ),
    );
    if (ok != true) return;
    final done = await _run(
      () async => _repo.complete(widget.id, decisions: _decisions),
      successMsg: 'Return collected',
    );
    if (done && mounted) Navigator.of(context).pop();
  }

  Future<void> _reject() async {
    final result = await showModalBottomSheet<(ReturnRejectReason, String)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ReasonSheet(
        title: 'Why are you rejecting this return?',
        reasons: ReturnRejectReason.values,
      ),
    );
    if (result == null) return;
    final done = await _run(
      () async => _repo.reject(widget.id,
          reason: result.$1, note: result.$2),
      successMsg: 'Return rejected',
    );
    if (done && mounted) Navigator.of(context).pop();
  }

  Future<void> _reschedule() async {
    final result =
        await showModalBottomSheet<(ReturnRescheduleReason, String)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ReasonSheet(
        title: 'Why are you rescheduling?',
        reasons: ReturnRescheduleReason.values,
      ),
    );
    if (result == null) return;
    final done = await _run(
      () async => _repo.reschedule(widget.id,
          reason: result.$1, note: result.$2),
      successMsg: 'Pickup rescheduled',
    );
    if (done && mounted) Navigator.of(context).pop();
  }

  int _requestedQty(ReturnPickup p, String lineId) =>
      p.items.firstWhere((i) => i.id == lineId).quantity;

  double _projectedRefund(ReturnPickup p) {
    var total = 0.0;
    for (final line in p.items) {
      final qty = _decisions[line.id] ?? line.quantity;
      total += line.unitPrice * qty;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(returnPickupDetailProvider(widget.id));
    return Scaffold(
      appBar: AppBar(title: const Text('Return Pickup')),
      body: async.when(
        loading: () => const Loading(),
        error: (_, __) => ErrorRetry(
          message: 'Could not load this pickup.',
          onRetry: () => ref.invalidate(returnPickupDetailProvider(widget.id)),
        ),
        data: (p) => _body(p),
      ),
    );
  }

  Widget _body(ReturnPickup p) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _header(p),
              const SizedBox(height: 16),
              _customerCard(p),
              const SizedBox(height: 16),
              const SectionHeader('What the customer sent'),
              _customerEvidence(p),
              const SizedBox(height: 16),
              const SectionHeader('Items'),
              ..._itemRows(p),
              const SizedBox(height: 16),
              const SectionHeader('Your condition photos'),
              _agentEvidence(p),
              const SizedBox(height: 80),
            ],
          ),
        ),
        _actionBar(p),
      ],
    );
  }

  Widget _header(ReturnPickup p) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(p.returnCode,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 18)),
                ),
                StatusPill(
                    label: returnStatusLabel(p.status),
                    color: returnStatusColor(p.status)),
              ],
            ),
            const SizedBox(height: 4),
            Text('Order ${p.orderCode}',
                style: const TextStyle(color: AgentColors.textSecondary)),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.info_outline,
                    size: 16, color: AgentColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(child: Text(p.reason)),
              ],
            ),
            if (p.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(p.description,
                  style: const TextStyle(color: AgentColors.textSecondary)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Refund if accepted',
                    style: TextStyle(color: AgentColors.textSecondary)),
                const Spacer(),
                Text(agentMoney(_projectedRefund(p)),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
              ],
            ),
          ],
        ),
      );

  Widget _customerCard(ReturnPickup p) => AppCard(
        child: Row(
          children: [
            const LeadingIcon(
                icon: Icons.person_rounded, color: AgentColors.brand),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      p.customerName.isNotEmpty ? p.customerName : 'Customer',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (p.address.isNotEmpty)
                    Text(p.address,
                        style: const TextStyle(
                            color: AgentColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            if (p.customerPhone.isNotEmpty)
              IconButton(
                tooltip: 'Call customer',
                icon: const Icon(Icons.phone_rounded,
                    color: AgentColors.green),
                onPressed: () => _call(p.customerPhone),
              ),
          ],
        ),
      );

  Widget _customerEvidence(ReturnPickup p) {
    final photos = p.customerPhotos;
    if (photos.isEmpty) {
      return const AppCard(
        child: Text('No photos were submitted with this return.',
            style: TextStyle(color: AgentColors.textSecondary)),
      );
    }
    return _photoStrip(photos, emptyHint: '');
  }

  Widget _agentEvidence(ReturnPickup p) {
    final photos = p.agentPhotos;
    if (photos.isEmpty) {
      return AppCard(
        child: Row(
          children: [
            const Icon(Icons.photo_camera_outlined,
                color: AgentColors.amber),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Take at least one photo of the item as you found it. '
                'Required before you can accept.',
                style: TextStyle(color: AgentColors.textSecondary),
              ),
            ),
          ],
        ),
      );
    }
    return _photoStrip(photos, emptyHint: '');
  }

  Widget _photoStrip(List<ReturnPhoto> photos, {required String emptyHint}) =>
      SizedBox(
        height: 96,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: photos.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ReturnPhotoView(photo: photos[i]),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 96,
                height: 96,
                child: ReturnPhotoThumb(photo: photos[i]),
              ),
            ),
          ),
        ),
      );

  List<Widget> _itemRows(ReturnPickup p) {
    final editable = p.isAtDoor;
    return p.items.map((line) {
      final accepted = _decisions[line.id] ?? line.quantity;
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(line.productName,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Text(agentMoney(line.unitPrice * accepted),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 4),
            Text('Customer wants to return ${line.quantity}',
                style: const TextStyle(
                    color: AgentColors.textSecondary, fontSize: 12)),
            if (editable) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Accepting',
                      style: TextStyle(color: AgentColors.textSecondary)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: accepted <= 0
                        ? null
                        : () => setState(
                            () => _decisions[line.id] = accepted - 1),
                  ),
                  Text('$accepted',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16)),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: accepted >= line.quantity
                        ? null
                        : () => setState(
                            () => _decisions[line.id] = accepted + 1),
                  ),
                ],
              ),
              if (accepted < line.quantity)
                Text(
                  'Rejecting ${line.quantity - accepted} of ${line.quantity}',
                  style: const TextStyle(
                      color: AgentColors.amber,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
            ],
          ],
        ),
      );
    }).toList();
  }

  /// The one action bar that changes with the state machine, so the agent only
  /// ever sees the step they can actually take next.
  Widget _actionBar(ReturnPickup p) {
    if (p.isTerminal) {
      return const SizedBox.shrink();
    }
    final children = <Widget>[];

    switch (p.status) {
      case 'assigned':
        children.add(_primary('Accept job', () => _run(
            () async => _repo.accept(widget.id),
            successMsg: 'Pickup accepted')));
        break;
      case 'accepted':
      case 'rescheduled':
        children.add(_primary('Start pickup', () => _run(
            () async => _repo.enRoute(widget.id),
            successMsg: 'On your way')));
        break;
      case 'en_route':
        children.add(_primary("I've reached", () => _run(
            () async => _repo.reach(widget.id),
            successMsg: 'Marked as reached')));
        break;
      case 'reached':
        children.addAll([
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _capturePhoto(p),
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(p.hasAgentPhoto ? 'Add another photo' : 'Take photo'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _reject,
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AgentColors.danger),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  // The backend rejects this too (RETURN_EVIDENCE_REQUIRED);
                  // disabling it here means the agent finds out before they
                  // have told the customer it is accepted.
                  onPressed: (_busy || !p.hasAgentPhoto)
                      ? null
                      : () => _accept(p),
                  child: const Text('Accept'),
                ),
              ),
            ],
          ),
          if (!p.hasAgentPhoto) ...[
            const SizedBox(height: 6),
            const Text(
              'Take a condition photo to enable Accept.',
              style: TextStyle(color: AgentColors.amber, fontSize: 12),
            ),
          ],
        ]);
        break;
    }

    if (p.status != 'assigned') {
      children.addAll([
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : _reschedule,
          child: const Text("Can't do it now — reschedule"),
        ),
      ]);
    }

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: AgentColors.bg,
          border: Border(top: BorderSide(color: AgentColors.divider)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }

  Widget _primary(String label, VoidCallback onTap) => SizedBox(
        width: double.infinity,
        child: FilledButton(
            onPressed: _busy ? null : onTap, child: Text(label)),
      );
}

/// Reason picker + optional note, shared by reject and reschedule.
class _ReasonSheet<T> extends StatefulWidget {
  const _ReasonSheet({required this.title, required this.reasons});
  final String title;
  final List<T> reasons;

  @override
  State<_ReasonSheet<T>> createState() => _ReasonSheetState<T>();
}

class _ReasonSheetState<T> extends State<_ReasonSheet<T>> {
  T? _selected;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String _label(T r) => (r as dynamic).label as String;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 12),
          for (final r in widget.reasons)
            RadioListTile<T>(
              value: r,
              groupValue: _selected,
              onChanged: (v) => setState(() => _selected = v),
              title: Text(_label(r)),
              contentPadding: EdgeInsets.zero,
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _note,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              hintText: 'Anything the store should know',
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _selected == null
                  ? null
                  : () => Navigator.pop(context, (_selected as T, _note.text)),
              child: const Text('Confirm'),
            ),
          ),
        ],
      ),
    );
  }
}
