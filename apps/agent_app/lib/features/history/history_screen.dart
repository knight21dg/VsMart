import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net_errors.dart';
import '../../core/ui.dart';
import '../collections/presentation/collection_detail_screen.dart';
import '../deliveries/presentation/delivery_detail_screen.dart';
import '../verification/presentation/verification_detail_screen.dart';
import 'history_data.dart';
import 'history_providers.dart';

/// Task history — the work an agent has finished.
///
/// The three task queues drop a task the moment it closes, so an agent had no
/// way to look back at what they did, or check a day's collections against a
/// payout. This is that record.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final nearEnd =
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 320;
    if (nearEnd) {
      // The controller guards re-entry, so firing on every scroll tick is safe.
      ref.read(historyControllerProvider.notifier).loadMore();
    }
  }

  Future<void> _pickRange() async {
    final filter = ref.read(historyFilterProvider);
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: filter.from != null && filter.to != null
          ? DateTimeRange(start: filter.from!, end: filter.to!)
          : null,
    );
    if (picked == null) return;
    ref
        .read(historyFilterProvider.notifier)
        .update((f) => f.withRange(picked.start, picked.end));
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(historyFilterProvider);
    final state = ref.watch(historyControllerProvider);

    return Scaffold(
      backgroundColor: AgentColors.bg,
      appBar: AppBar(
        title: const Text('Task history'),
        actions: [
          IconButton(
            tooltip: filter.hasRange ? 'Change dates' : 'Filter by date',
            icon: Icon(
              filter.hasRange
                  ? Icons.event_available_rounded
                  : Icons.date_range_rounded,
              color: filter.hasRange
                  ? AgentColors.brandBright
                  : AgentColors.textSecondary,
            ),
            onPressed: _pickRange,
          ),
        ],
      ),
      body: Column(
        children: [
          _KindTabs(
            selected: filter.kind,
            onSelect: (k) => ref
                .read(historyFilterProvider.notifier)
                .update((f) => f.withKind(k)),
          ),
          if (filter.hasRange) _RangeChip(filter: filter),
          Expanded(child: _body(state)),
        ],
      ),
    );
  }

  Widget _body(HistoryState state) {
    if (state.loading) return const Loading();

    if (state.error != null && state.items.isEmpty) {
      final e = state.error!;
      return ErrorRetry(
        message: describeFailure(e, fallback: 'Could not load your history.').display,
        onRetry: () => ref.read(historyControllerProvider.notifier).refresh(),
      );
    }

    if (state.isEmpty) {
      return const EmptyState(
        icon: Icons.history_rounded,
        title: 'Nothing here yet',
        message: 'Tasks you finish will show up here.',
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(historyControllerProvider.notifier).refresh(),
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        // +1 header, +1 footer (spinner / end-of-list).
        itemCount: state.items.length + 2,
        itemBuilder: (context, i) {
          if (i == 0) return _Summary(state: state);
          if (i == state.items.length + 1) return _Footer(state: state);
          return _HistoryRow(entry: state.items[i - 1]);
        },
      ),
    );
  }
}

class _KindTabs extends StatelessWidget {
  const _KindTabs({required this.selected, required this.onSelect});

  final HistoryKind? selected;
  final ValueChanged<HistoryKind?> onSelect;

  @override
  Widget build(BuildContext context) {
    final options = <(HistoryKind?, String)>[
      (null, 'All'),
      (HistoryKind.delivery, 'Deliveries'),
      (HistoryKind.collection, 'Collections'),
      (HistoryKind.verification, 'Verifications'),
    ];
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (kind, label) = options[i];
          final active = kind == selected;
          return GestureDetector(
            onTap: () => onSelect(kind),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: active ? AgentColors.brandBright : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: active ? AgentColors.brandBright : AgentColors.border,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : AgentColors.label,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({required this.filter});

  final HistoryFilter filter;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        return Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: InputChip(
              label: Text(
                '${_fmt(filter.from)} → ${_fmt(filter.to)}',
                style: const TextStyle(fontSize: 12),
              ),
              onDeleted: () => ref
                  .read(historyFilterProvider.notifier)
                  .update((f) => f.withRange(null, null)),
            ),
          ),
        );
      },
    );
  }

  static String _fmt(DateTime? d) =>
      d == null ? 'Any' : '${d.day}/${d.month}/${d.year}';
}

class _Summary extends StatelessWidget {
  const _Summary({required this.state});

  final HistoryState state;

  @override
  Widget build(BuildContext context) {
    final counts = state.counts;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: 'Tasks closed',
                  value: '${state.total}',
                  accent: AgentColors.brand,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  label: 'Cash collected',
                  value: agentMoney(state.collectedTotal),
                  accent: AgentColors.green,
                ),
              ),
            ],
          ),
          if (counts.length > 1) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final kind in HistoryKind.values)
                  if ((counts[kind.code] ?? 0) > 0)
                    StatusPill(
                      label: '${kind.label} ${counts[kind.code]}',
                      color: _kindColor(kind),
                    ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final HistoryEntry entry;

  void _openDetail(BuildContext context) {
    if (entry.id.isEmpty) return;
    final screen = switch (entry.kind) {
      HistoryKind.delivery => DeliveryDetailScreen(
        id: entry.id,
        orderCode: entry.reference,
      ),
      HistoryKind.collection => CollectionDetailScreen(
        id: entry.id,
        customerName: entry.customerName,
      ),
      HistoryKind.verification => VerificationDetailScreen(
        id: entry.id,
        customerName: entry.customerName,
      ),
    };
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: entry.id.isEmpty ? null : () => _openDetail(context),
        child: AppCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LeadingIcon(
                icon: _kindIcon(entry.kind),
                color: _kindColor(entry.kind),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AgentColors.textPrimary,
                      ),
                    ),
                    if (entry.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        entry.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AgentColors.textSecondary,
                        ),
                      ),
                    ],
                    // A partial collection is the one case where the agent needs
                    // to see both figures — what came in vs what was owed.
                    if (entry.outcome == HistoryOutcome.partial &&
                        entry.amountDue != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${agentMoney(entry.amount ?? 0)} of '
                        '${agentMoney(entry.amountDue!)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AgentColors.amber,
                        ),
                      ),
                    ],
                    if (entry.failureReason.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        entry.failureReason.replaceAll('_', ' '),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AgentColors.danger,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        StatusPill(
                          label: entry.outcome.label,
                          color: _outcomeColor(entry.outcome),
                        ),
                        const Spacer(),
                        if (entry.closedAt != null)
                          Text(
                            _when(entry.closedAt!),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AgentColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _when(DateTime d) {
    final now = DateTime.now();
    final sameDay =
        d.year == now.year && d.month == now.month && d.day == now.day;
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    if (sameDay) return 'Today $hh:$mm';
    return '${d.day}/${d.month} $hh:$mm';
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.state});

  final HistoryState state;

  @override
  Widget build(BuildContext context) {
    if (state.loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (state.hasMore) return const SizedBox(height: 24);
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Text(
          'That\'s everything',
          style: TextStyle(fontSize: 12, color: AgentColors.textSecondary),
        ),
      ),
    );
  }
}

Color _kindColor(HistoryKind kind) => switch (kind) {
  HistoryKind.delivery => AgentColors.blue,
  HistoryKind.collection => AgentColors.brand,
  HistoryKind.verification => AgentColors.pink,
};

IconData _kindIcon(HistoryKind kind) => switch (kind) {
  HistoryKind.delivery => Icons.local_shipping_rounded,
  HistoryKind.collection => Icons.account_balance_wallet_rounded,
  HistoryKind.verification => Icons.verified_user_rounded,
};

Color _outcomeColor(HistoryOutcome outcome) => switch (outcome) {
  HistoryOutcome.success => AgentColors.green,
  HistoryOutcome.partial => AgentColors.amber,
  HistoryOutcome.failed => AgentColors.danger,
};
