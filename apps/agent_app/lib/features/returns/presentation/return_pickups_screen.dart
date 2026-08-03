import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui.dart';
import '../data/returns_data.dart';
import '../returns_providers.dart';
import 'return_pickup_detail_screen.dart';

/// Friendly label for a return-pickup state-machine status.
String returnStatusLabel(String status) {
  switch (status) {
    case 'assigned':
      return 'Assigned';
    case 'accepted':
      return 'Accepted';
    case 'en_route':
      return 'En Route';
    case 'reached':
      return 'At Customer';
    case 'completed':
      return 'Collected';
    case 'rejected':
      return 'Rejected';
    case 'rescheduled':
      return 'Rescheduled';
    case 'reassigned':
      return 'Reassigned';
    case 'cancelled':
      return 'Cancelled';
    default:
      return status.isEmpty
          ? 'Unknown'
          : status[0].toUpperCase() + status.substring(1).replaceAll('_', ' ');
  }
}

/// Pill colour: collected → green, in-progress → brand, rescheduled → amber,
/// rejected/cancelled → danger, freshly-assigned → amber.
Color returnStatusColor(String status) {
  switch (status) {
    case 'completed':
      return AgentColors.green;
    case 'accepted':
    case 'en_route':
    case 'reached':
      return AgentColors.brand;
    case 'rescheduled':
      return AgentColors.amber;
    case 'rejected':
    case 'cancelled':
    case 'reassigned':
      return AgentColors.danger;
    default:
      return AgentColors.amber;
  }
}

/// Lists the doorstep return pickups assigned to the signed-in agent.
class ReturnPickupsScreen extends ConsumerWidget {
  const ReturnPickupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(assignedReturnPickupsProvider);
    final count = async.valueOrNull?.length ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(count > 0 ? 'Return Pickups ($count)' : 'Return Pickups'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(assignedReturnPickupsProvider.future),
        child: async.when(
          loading: () => const Loading(),
          error: (_, __) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: ErrorRetry(
                  message: 'Could not load your return pickups.',
                  onRetry: () =>
                      ref.invalidate(assignedReturnPickupsProvider),
                ),
              ),
            ],
          ),
          data: (pickups) {
            if (pickups.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.7,
                    child: const EmptyState(
                      icon: Icons.assignment_return_outlined,
                      title: 'No return pickups',
                      message:
                          'When a customer raises a return, it will appear here.',
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: pickups.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) => _PickupCard(pickup: pickups[i]),
            );
          },
        ),
      ),
    );
  }
}

class _PickupCard extends StatelessWidget {
  const _PickupCard({required this.pickup});
  final ReturnPickup pickup;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ReturnPickupDetailScreen(id: pickup.id),
        ),
      ),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                LeadingIcon(
                    icon: Icons.assignment_return_rounded,
                    color: returnStatusColor(pickup.status)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pickup.customerName.isNotEmpty
                            ? pickup.customerName
                            : 'Customer',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      Text(
                        pickup.returnCode,
                        style: const TextStyle(
                            color: AgentColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                StatusPill(
                  label: returnStatusLabel(pickup.status),
                  color: returnStatusColor(pickup.status),
                ),
              ],
            ),
            if (pickup.reason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 16, color: AgentColors.textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(pickup.reason,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AgentColors.textSecondary)),
                  ),
                ],
              ),
            ],
            if (pickup.address.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 16, color: AgentColors.textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(pickup.address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AgentColors.textSecondary, fontSize: 12)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '${pickup.items.length} item'
                  '${pickup.items.length == 1 ? '' : 's'}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Text('• ${agentMoney(pickup.refundAmount)} refund',
                    style:
                        const TextStyle(color: AgentColors.textSecondary)),
                if (pickup.attemptNo > 1) ...[
                  const SizedBox(width: 8),
                  Text('• attempt ${pickup.attemptNo}',
                      style: const TextStyle(color: AgentColors.amber)),
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
