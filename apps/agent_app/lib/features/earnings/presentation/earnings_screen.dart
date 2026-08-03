import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui.dart';
import '../../dashboard/data/dashboard_data.dart';
import '../../dashboard/presentation/dashboard_providers.dart';

/// Earnings & Incentives — the agent's pay breakdown and recent incentive rows.
/// Backed by GET /agents/earnings and GET /agents/incentives.
class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final earnings = ref.watch(agentEarningsProvider);
    final incentives = ref.watch(agentIncentivesProvider);

    return Scaffold(
      backgroundColor: AgentColors.bg,
      appBar: AppBar(title: const Text('Earnings & Incentives')),
      body: earnings.when(
        loading: () => const Loading(),
        error: (_, __) => ErrorRetry(
          message: "Couldn't load your earnings.",
          onRetry: () => ref.invalidate(agentEarningsProvider),
        ),
        data: (e) => RefreshIndicator(
          color: AgentColors.brand,
          onRefresh: () async {
            ref.invalidate(agentEarningsProvider);
            ref.invalidate(agentIncentivesProvider);
            await ref.read(agentEarningsProvider.future).catchError((_) => e);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _TotalCard(earnings: e),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: StatTile(
                    label: 'Base Pay',
                    value: agentMoney(e.base),
                    accent: AgentColors.brand,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatTile(
                    label: 'Incentives',
                    value: agentMoney(e.incentives),
                    accent: AgentColors.amber,
                  ),
                ),
              ]),
              const SizedBox(height: 24),
              const SectionHeader('Recent Incentives'),
              incentives.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => const AppCard(
                  child: Text("Couldn't load incentives.",
                      style: TextStyle(color: AgentColors.textSecondary)),
                ),
                data: (rows) => rows.isEmpty
                    ? const AppCard(
                        child: Text('No incentives yet.',
                            style: TextStyle(color: AgentColors.textSecondary)),
                      )
                    : AppCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (var i = 0; i < rows.length; i++) ...[
                              if (i > 0)
                                const Divider(
                                    height: 1, color: AgentColors.divider),
                              _IncentiveRow(row: rows[i]),
                            ],
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.earnings});
  final AgentEarnings earnings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AgentColors.brand,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Color(0x1A000000), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('TOTAL EARNINGS',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: Color(0xCCFFFFFF))),
          const SizedBox(height: 6),
          Text(agentMoney(earnings.total),
              style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ],
      ),
    );
  }
}

class _IncentiveRow extends StatelessWidget {
  const _IncentiveRow({required this.row});
  final AgentIncentive row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: AgentColors.amber.withValues(alpha: 0.15),
                shape: BoxShape.circle),
            child: const Icon(Icons.emoji_events_rounded,
                color: AgentColors.amber, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.reason.isNotEmpty ? row.reason : 'Incentive',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AgentColors.textPrimary)),
                if (row.period.isNotEmpty)
                  Text(row.period,
                      style: const TextStyle(
                          fontSize: 12, color: AgentColors.textSecondary)),
              ],
            ),
          ),
          Text('+${agentMoney(row.amount)}',
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AgentColors.brand)),
        ],
      ),
    );
  }
}
