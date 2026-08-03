import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui.dart';
import '../../dashboard/data/dashboard_data.dart';
import '../../dashboard/presentation/dashboard_providers.dart';

const _weekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// Performance — the agent's completed-work analytics (GET /agents/performance).
///
/// Used to be three bare numbers. Now leads with a 14-day trend chart (so an
/// agent can see whether they're picking up or slowing down, not just a
/// lifetime total) plus a proportional breakdown bar, with the per-type
/// counts underneath for the exact figures.
class PerformanceScreen extends ConsumerWidget {
  const PerformanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perf = ref.watch(agentPerformanceProvider);
    return Scaffold(
      backgroundColor: AgentColors.bg,
      appBar: AppBar(title: const Text('Performance')),
      body: perf.when(
        loading: () => const Loading(),
        error: (_, __) => ErrorRetry(
          message: "Couldn't load your performance.",
          onRetry: () => ref.invalidate(agentPerformanceProvider),
        ),
        data: (p) {
          final total =
              p.deliveriesCompleted + p.collectionsDone + p.verificationsDone;
          return RefreshIndicator(
            color: AgentColors.brand,
            onRefresh: () async {
              ref.invalidate(agentPerformanceProvider);
              await ref.read(agentPerformanceProvider.future).catchError((_) => p);
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AgentColors.navy,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TASKS COMPLETED',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6,
                              color: Color(0x99EDF0FF))),
                      const SizedBox(height: 6),
                      Text('$total',
                          style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFEDF0FF))),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (p.daily.isNotEmpty) ...[
                  const SectionHeader('Last 14 days'),
                  AppCard(child: _TrendChart(days: p.daily)),
                  const SizedBox(height: 20),
                ],
                const SectionHeader('Breakdown'),
                if (total > 0) ...[
                  AppCard(
                    child: _BreakdownBar(
                      deliveries: p.deliveriesCompleted,
                      collections: p.collectionsDone,
                      verifications: p.verificationsDone,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(children: [
                  Expanded(
                    child: StatTile(
                      label: 'Deliveries',
                      value: '${p.deliveriesCompleted}',
                      accent: AgentColors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatTile(
                      label: 'Collections',
                      value: '${p.collectionsDone}',
                      accent: AgentColors.brand,
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                StatTile(
                  label: 'Verifications',
                  value: '${p.verificationsDone}',
                  accent: AgentColors.pink,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// A stacked daily bar chart — one bar per day, segmented by task type, scaled
/// to the busiest day in the window so relative effort is legible at a glance.
class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.days});

  final List<AgentPerformanceDay> days;

  static const _barMaxHeight = 96.0;

  @override
  Widget build(BuildContext context) {
    final busiest = days.fold<int>(1, (m, d) => d.total > m ? d.total : m);
    return Column(
      children: [
        SizedBox(
          height: _barMaxHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final day in days)
                Expanded(child: _DayBar(day: day, busiest: busiest, maxHeight: _barMaxHeight)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final day in days)
              Expanded(
                child: Text(
                  _weekdayLabels[(day.date.weekday - 1) % 7],
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10, color: AgentColors.textSecondary),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        const Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            _LegendDot(color: AgentColors.blue, label: 'Deliveries'),
            _LegendDot(color: AgentColors.brand, label: 'Collections'),
            _LegendDot(color: AgentColors.pink, label: 'Verifications'),
          ],
        ),
      ],
    );
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({required this.day, required this.busiest, required this.maxHeight});

  final AgentPerformanceDay day;
  final int busiest;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final scale = maxHeight / busiest;
    final segments = [
      (day.deliveries, AgentColors.blue),
      (day.collections, AgentColors.brand),
      (day.verifications, AgentColors.pink),
    ].where((s) => s.$1 > 0).toList();

    return Tooltip(
      message: '${day.total} on ${day.date.day}/${day.date.month}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: day.total == 0
            ? Container(
                height: 3,
                decoration: BoxDecoration(
                  color: AgentColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (count, color) in segments)
                    Container(
                      height: (count * scale).clamp(3.0, maxHeight),
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: segments.last == (count, color)
                            ? const BorderRadius.vertical(top: Radius.circular(3))
                            : null,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(fontSize: 11, color: AgentColors.textSecondary)),
      ],
    );
  }
}

/// A single proportional bar showing how the lifetime total splits across the
/// three task types — the "shape" of an agent's work at a glance.
class _BreakdownBar extends StatelessWidget {
  const _BreakdownBar({
    required this.deliveries,
    required this.collections,
    required this.verifications,
  });

  final int deliveries;
  final int collections;
  final int verifications;

  @override
  Widget build(BuildContext context) {
    final total = deliveries + collections + verifications;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 12,
            child: Row(
              children: [
                if (deliveries > 0)
                  Expanded(flex: deliveries, child: Container(color: AgentColors.blue)),
                if (collections > 0)
                  Expanded(flex: collections, child: Container(color: AgentColors.brand)),
                if (verifications > 0)
                  Expanded(flex: verifications, child: Container(color: AgentColors.pink)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            _LegendDot(
              color: AgentColors.blue,
              label: '${(deliveries * 100 / total).round()}% deliveries',
            ),
            _LegendDot(
              color: AgentColors.brand,
              label: '${(collections * 100 / total).round()}% collections',
            ),
            _LegendDot(
              color: AgentColors.pink,
              label: '${(verifications * 100 / total).round()}% verifications',
            ),
          ],
        ),
      ],
    );
  }
}
