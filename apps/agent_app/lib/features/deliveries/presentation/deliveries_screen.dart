import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui.dart';
import '../data/deliveries_data.dart';
import 'batch_route_screen.dart';
import 'delivery_detail_screen.dart';
import 'deliveries_providers.dart';

/// Friendly label for a delivery state-machine status value.
String deliveryStatusLabel(String status) {
  switch (status) {
    case 'assigned':
      return 'Assigned';
    case 'accepted':
      return 'Accepted';
    case 'picked_up':
      return 'Picked Up';
    case 'out_for_delivery':
      return 'Out for Delivery';
    case 'reached':
      return 'Reached';
    case 'delivered':
      return 'Delivered';
    case 'rejected':
      return 'Rejected';
    case 'cancelled':
      return 'Cancelled';
    case 'failed':
      return 'Failed';
    // Legacy / payment-status values kept for the order summary card.
    case 'pending':
      return 'Pending';
    case 'paid':
      return 'Paid';
    default:
      return status.isEmpty
          ? 'Unknown'
          : status[0].toUpperCase() + status.substring(1).replaceAll('_', ' ');
  }
}

/// Pill colour: delivered → green, in-progress → brand,
/// rejected/cancelled/failed → danger, freshly-assigned → amber.
Color deliveryStatusColor(String status) {
  switch (status) {
    case 'delivered':
    case 'paid':
      return AgentColors.green;
    case 'accepted':
    case 'picked_up':
    case 'out_for_delivery':
    case 'reached':
      return AgentColors.brand;
    case 'rejected':
    case 'cancelled':
    case 'failed':
      return AgentColors.danger;
    default:
      return AgentColors.amber;
  }
}

/// Lists the orders assigned to the signed-in agent.
class DeliveriesScreen extends ConsumerWidget {
  const DeliveriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(assignedDeliveriesProvider);
    final count = async.valueOrNull?.length ?? 0;
    return Scaffold(
      appBar: AppBar(
          title: Text(count > 0 ? 'Deliveries ($count)' : 'Deliveries')),
      body: Column(
        children: [
          const _ActiveRouteBanner(),
          Expanded(
            child: RefreshIndicator(
        onRefresh: () => ref.refresh(assignedDeliveriesProvider.future),
        child: async.when(
          loading: () => const Loading(),
          error: (_, __) => ListView(
            // ListView so pull-to-refresh works even in the error state.
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: ErrorRetry(
                  message: 'Could not load your deliveries.',
                  onRetry: () => ref.invalidate(assignedDeliveriesProvider),
                ),
              ),
            ],
          ),
          data: (deliveries) {
            if (deliveries.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.7,
                    child: const EmptyState(
                      icon: Icons.local_shipping_outlined,
                      title: 'No deliveries assigned',
                      message: 'New assignments will appear here.',
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: deliveries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) =>
                  _DeliveryCard(delivery: deliveries[i]),
            );
          },
        ),
      ),
          ),
        ],
      ),
    );
  }
}

class _ActiveRouteBanner extends ConsumerWidget {
  const _ActiveRouteBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batch = ref.watch(currentBatchProvider).asData?.value;
    if (batch == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const BatchRouteScreen())),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AgentColors.brand, AgentColors.brandDark]),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.route_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Active route',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    Text(
                      '${batch.doneStops}/${batch.totalStops} stops · ${batch.totalDistanceKm} km · ~${batch.etaMinutes} min',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({required this.delivery});
  final AgentDelivery delivery;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              DeliveryDetailScreen(id: delivery.id, orderCode: delivery.orderCode),
        ),
      ),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                LeadingIcon(
                    icon: Icons.local_shipping_rounded,
                    color: deliveryStatusColor(delivery.status)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    delivery.orderCode.isNotEmpty ? delivery.orderCode : 'Order',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                StatusPill(
                  label: deliveryStatusLabel(delivery.status),
                  color: deliveryStatusColor(delivery.status),
                ),
              ],
            ),
            if (delivery.customerName.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.person_outline,
                      size: 16, color: AgentColors.textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(delivery.customerName,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
            if (delivery.address.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 16, color: AgentColors.textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      delivery.address,
                      style: const TextStyle(color: AgentColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '₹${delivery.amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
                if (delivery.itemCount > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '• ${delivery.itemCount} item${delivery.itemCount == 1 ? '' : 's'}',
                    style: const TextStyle(color: AgentColors.textSecondary),
                  ),
                ],
                if (delivery.distanceKm > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '• ${delivery.distanceKm.toStringAsFixed(1)} km',
                    style: const TextStyle(color: AgentColors.textSecondary),
                  ),
                ],
                const Spacer(),
                const Icon(Icons.chevron_right,
                    color: AgentColors.textSecondary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
