import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui.dart';
import '../../cash/cash_providers.dart';
import '../../cash/cash_screen.dart';
import '../collections_providers.dart';
import '../data/collections_data.dart';
import 'collection_detail_screen.dart';

/// Friendly label for a collection state-machine status value.
String collectionStatusLabel(String status) {
  switch (status) {
    case 'requested':
      return 'Requested';
    case 'assigned':
      return 'Assigned';
    case 'accepted':
      return 'Accepted';
    case 'en_route':
      return 'En Route';
    case 'reached':
      return 'Reached';
    case 'collected':
      return 'Collected';
    case 'partially_collected':
      return 'Partially Collected';
    case 'disputed':
      return 'Disputed';
    case 'rejected':
      return 'Rejected';
    case 'cancelled':
      return 'Cancelled';
    case 'failed':
      return 'Failed';
    default:
      return status.isEmpty
          ? 'Unknown'
          : status[0].toUpperCase() + status.substring(1).replaceAll('_', ' ');
  }
}

/// Pill colour: collected → green, in-progress → brand, partial → amber,
/// rejected/cancelled/failed/disputed → danger, freshly-assigned → amber.
Color collectionStatusColor(String status) {
  switch (status) {
    case 'collected':
      return AgentColors.green;
    case 'accepted':
    case 'en_route':
    case 'reached':
      return AgentColors.brand;
    case 'partially_collected':
      return AgentColors.amber;
    case 'rejected':
    case 'cancelled':
    case 'failed':
    case 'disputed':
      return AgentColors.danger;
    default:
      return AgentColors.amber;
  }
}

String _money(double v) => agentMoney(v);

/// Lists the cash-recovery tasks assigned to the signed-in agent.
class CollectionsScreen extends ConsumerWidget {
  const CollectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(assignedCollectionsProvider);
    final count = async.valueOrNull?.length ?? 0;
    final held = ref.watch(cashSummaryProvider).valueOrNull?.inHand ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(count > 0 ? 'Collections ($count)' : 'Collections'),
        actions: [
          // Cash lives here because this is where it comes from. The badge shows
          // what the agent is still holding, so undeposited cash is visible
          // rather than something they have to remember.
          IconButton(
            tooltip: 'Cash with you',
            icon: Badge(
              isLabelVisible: held > 0,
              label: Text(agentMoney(held)),
              child: const Icon(Icons.account_balance_wallet_outlined),
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CashScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(assignedCollectionsProvider.future),
        child: async.when(
          loading: () => const Loading(),
          error: (_, __) => ListView(
            // ListView so pull-to-refresh works even in the error state.
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: ErrorRetry(
                  message: 'Could not load your collections.',
                  onRetry: () => ref.invalidate(assignedCollectionsProvider),
                ),
              ),
            ],
          ),
          data: (collections) {
            if (collections.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.7,
                    child: const EmptyState(
                      icon: Icons.payments_outlined,
                      title: 'No collections assigned',
                      message: 'New cash-recovery tasks will appear here.',
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: collections.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) =>
                  _CollectionCard(collection: collections[i]),
            );
          },
        ),
      ),
    );
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({required this.collection});
  final AgentCollection collection;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CollectionDetailScreen(
              id: collection.id, customerName: collection.customerName),
        ),
      ),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                LeadingIcon(
                    icon: Icons.account_balance_wallet_rounded,
                    color: collectionStatusColor(collection.status)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    collection.customerName.isNotEmpty
                        ? collection.customerName
                        : 'Customer',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                StatusPill(
                  label: collectionStatusLabel(collection.status),
                  color: collectionStatusColor(collection.status),
                ),
              ],
            ),
            if (collection.isPriority || collection.escalated) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (collection.isPriority)
                    const _MiniBadge(
                        label: 'PRIORITY',
                        icon: Icons.priority_high_rounded,
                        color: AgentColors.amber),
                  if (collection.isPriority && collection.escalated)
                    const SizedBox(width: 6),
                  if (collection.escalated)
                    const _MiniBadge(
                        label: 'ESCALATED',
                        icon: Icons.trending_up_rounded,
                        color: AgentColors.danger),
                ],
              ),
            ],
            if (collection.customerPhone.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.phone_outlined,
                      size: 16, color: AgentColors.textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(collection.customerPhone,
                        style: const TextStyle(
                            color: AgentColors.textSecondary)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  _money(collection.amount),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
                if (collection.collectedAmount > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '• ${_money(collection.collectedAmount)} collected',
                    style: const TextStyle(color: AgentColors.green),
                  ),
                ] else if (collection.amountDue > 0 &&
                    collection.amountDue != collection.amount) ...[
                  const SizedBox(width: 8),
                  Text(
                    '• ${_money(collection.amountDue)} due',
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

class _MiniBadge extends StatelessWidget {
  const _MiniBadge(
      {required this.label, required this.icon, required this.color});
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
