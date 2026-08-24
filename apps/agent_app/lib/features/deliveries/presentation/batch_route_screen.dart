import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/ui.dart';
import '../../collections/presentation/collection_detail_screen.dart';
import '../data/batch_data.dart';
import 'deliveries_providers.dart';
import 'delivery_detail_screen.dart';
import 'route_map.dart';

/// The agent's guided trip: a store-optimized, sequenced set of stops (deliveries
/// + on-route collections). The agent never picks work — they accept the trip,
/// confirm the store pickup, then work the stops in order. Each stop opens the
/// existing delivery/collection detail flow (arrive → OTP → POD / collect).
class BatchRouteScreen extends ConsumerStatefulWidget {
  const BatchRouteScreen({super.key});

  @override
  ConsumerState<BatchRouteScreen> createState() => _BatchRouteScreenState();
}

class _BatchRouteScreenState extends ConsumerState<BatchRouteScreen> {
  final _pickup = TextEditingController();
  bool _busy = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // Keep the trip live — reflects a store-side reassignment within ~20s.
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && !_busy) ref.invalidate(currentBatchProvider);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _pickup.dispose();
    super.dispose();
  }

  Future<void> _abandon(RouteBatch b) async {
    final prePickup = b.needsAccept || b.needsPickup;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(prePickup ? 'Reject this trip?' : 'Report an issue?'),
        content: Text(prePickup
            ? 'The trip goes back to the store and is reassigned to another rider.'
            : 'Your remaining stops go back to the store and are reassigned. Completed stops stay done.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(prePickup ? 'Reject' : 'Report issue',
                style: const TextStyle(color: AgentColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(batchRepoProvider).abandon(b.id, prePickup ? 'agent_rejected' : 'agent_issue');
      ref.invalidate(currentBatchProvider);
      _snack('Trip released — the store will reassign it.');
      if (mounted) Navigator.of(context).maybePop();
    } catch (_) {
      _snack('Could not release the trip.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? AgentColors.danger : null,
      ));
  }

  Future<void> _accept(int id) async {
    setState(() => _busy = true);
    try {
      await ref.read(batchRepoProvider).accept(id);
      ref.invalidate(currentBatchProvider);
      _snack('Trip accepted — head to the store to pick up.');
    } catch (_) {
      _snack('Could not accept the trip.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickupConfirm(int id) async {
    final code = _pickup.text.trim();
    if (code.length < 4) {
      _snack('Enter the pickup code from the store.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(batchRepoProvider).pickup(id, code);
      ref.invalidate(currentBatchProvider);
      _pickup.clear();
      _snack('Picked up — your route is live.');
    } catch (_) {
      _snack('Invalid pickup code. Check with the store.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _navigate(RouteStop s) async {
    if (s.lat == null || s.lng == null) return;
    // google.navigation launches true turn-by-turn; fall back to the maps URL —
    // same order as active_delivery_map_screen.dart's _navigateExternal.
    //
    // The fallback is unconditional, not gated behind another canLaunchUrl
    // check: gating it meant a false negative from the FIRST check (e.g. no
    // <queries> entry for the google.navigation scheme — see
    // AndroidManifest.xml) left the button doing nothing at all, with no
    // feedback, on the one screen an agent running a multi-stop trip actually
    // depends on to get moving.
    final nav = Uri.parse('google.navigation:q=${s.lat},${s.lng}');
    if (await canLaunchUrl(nav)) {
      await launchUrl(nav);
      return;
    }
    final maps = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${s.lat},${s.lng}');
    final opened = await launchUrl(maps, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      _snack('Could not open navigation for this stop.', error: true);
    }
  }

  Future<void> _openStop(RouteStop s) async {
    if (s.isDelivery && s.taskId != null) {
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => DeliveryDetailScreen(id: s.taskId!, orderCode: s.orderCode ?? ''),
      ));
    } else if (s.collectionId != null) {
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => CollectionDetailScreen(id: s.collectionId!, customerName: s.label),
      ));
    }
    ref.invalidate(currentBatchProvider);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(currentBatchProvider);
    final batch = async.asData?.value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('My route'),
        actions: [
          if (batch != null && batch.status != 'completed')
            IconButton(
              icon: const Icon(Icons.report_gmailerrorred_rounded),
              tooltip: 'Reject / report issue',
              onPressed: _busy ? null : () => _abandon(batch),
            ),
        ],
      ),
      body: async.when(
        loading: () => const Loading(),
        error: (_, __) => ErrorRetry(onRetry: () => ref.invalidate(currentBatchProvider)),
        data: (batch) {
          if (batch == null) {
            return _empty();
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(currentBatchProvider.future),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _summary(batch),
                const SizedBox(height: 12),
                if (batch.needsAccept) _acceptCard(batch),
                if (batch.needsPickup) _pickupCard(batch),
                if (batch.inProgress || batch.status == 'completed') ...[
                  RouteMap(batch: batch),
                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 6, top: 4),
                    child: Text('Stops', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  ...batch.stops.map((s) => _stopTile(s, batch)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _empty() => ListView(children: const [
        SizedBox(height: 120),
        Icon(Icons.route_rounded, size: 56, color: AgentColors.textSecondary),
        SizedBox(height: 12),
        Center(child: Text('No active trip', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
        SizedBox(height: 4),
        Center(child: Text('New routes appear here when the store assigns them.',
            style: TextStyle(color: AgentColors.textSecondary))),
      ]);

  Widget _summary(RouteBatch b) {
    final pct = b.totalStops == 0 ? 0.0 : b.doneStops / b.totalStops;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AgentColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AgentColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront_rounded, size: 18, color: AgentColors.brand),
              const SizedBox(width: 6),
              Expanded(child: Text('Pickup: ${b.storeName}', style: const TextStyle(fontWeight: FontWeight.w700))),
              if (b.priority.isNotEmpty && b.priority != 'normal')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: AgentColors.amber.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                  child: Text(b.priority, style: const TextStyle(color: AgentColors.amber, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text('${b.totalStops} stops · ${b.totalDistanceKm} km · ~${b.etaMinutes} min',
              style: const TextStyle(color: AgentColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: pct, minHeight: 7, backgroundColor: AgentColors.border, color: AgentColors.green),
          ),
          const SizedBox(height: 4),
          Text('${b.doneStops}/${b.totalStops} done', style: const TextStyle(fontSize: 12, color: AgentColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _acceptCard(RouteBatch b) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AgentColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AgentColors.border)),
        child: Column(
          children: [
            const Text('You have a new trip. Accept to start.', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _busy ? null : () => _accept(b.id),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Accept trip'),
            ),
          ],
        ),
      );

  Widget _pickupCard(RouteBatch b) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AgentColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AgentColors.border)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Confirm pickup', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Enter the pickup code shown on the store dispatch board.',
                style: TextStyle(color: AgentColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: _pickup,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                hintText: '6-digit pickup code',
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _busy ? null : () => _pickupConfirm(b.id),
              icon: const Icon(Icons.local_shipping_rounded),
              label: const Text('Confirm pickup'),
            ),
          ],
        ),
      );

  Widget _stopTile(RouteStop s, RouteBatch b) {
    final done = s.status == 'done';
    final failed = s.status == 'failed';
    final color = done ? AgentColors.green : failed ? AgentColors.danger : AgentColors.brand;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: AgentColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AgentColors.border)),
      child: ListTile(
        onTap: () => _openStop(s),
        leading: CircleAvatar(
          radius: 15,
          backgroundColor: color,
          child: done
              ? const Icon(Icons.check, size: 16, color: Colors.white)
              : Text('${s.sequence}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
        ),
        title: Text(
          s.isDelivery ? s.label : 'Collect ${s.label}',
          style: const TextStyle(fontWeight: FontWeight.w600),
          maxLines: 1, overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          s.isDelivery
              ? '${s.orderCode ?? ''}${s.address.isNotEmpty ? ' · ${s.address}' : ''}'
              : 'Cash collection · ₹${s.amount.toStringAsFixed(0)}',
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.navigation_rounded, color: AgentColors.brand),
              tooltip: 'Navigate',
              onPressed: () => _navigate(s),
            ),
            const Icon(Icons.chevron_right_rounded, color: AgentColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
