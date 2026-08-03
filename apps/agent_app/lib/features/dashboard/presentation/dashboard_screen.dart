import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/services/presence_controller.dart';
import '../../../core/ui.dart';
import '../../cash/cash_providers.dart';
import '../../cash/cash_screen.dart';
import '../../collections/collections_providers.dart';
import '../../collections/presentation/collection_detail_screen.dart';
import '../../deliveries/data/deliveries_data.dart';
import '../../deliveries/presentation/deliveries_providers.dart';
import '../../deliveries/presentation/delivery_detail_screen.dart';
import '../../earnings/presentation/earnings_screen.dart';
import '../../verification/presentation/verification_detail_screen.dart';
import '../../history/history_providers.dart';
import '../../history/history_screen.dart';
import '../../notifications/presentation/notification_bell.dart';
import '../../performance/presentation/performance_screen.dart';
import '../../returns/presentation/return_pickup_detail_screen.dart';
import '../../returns/presentation/return_pickups_screen.dart';
import '../../returns/returns_providers.dart';
import '../../support/presentation/support_screen.dart';
import '../../verification/presentation/verification_providers.dart';
import '../data/dashboard_data.dart';
import 'dashboard_providers.dart';

/// Agent home, laid out in the ledger-app style the client asked for: a grid of
/// tappable money/count tiles up top, a running activity feed below, and the
/// day's two primary actions pinned to the bottom.
///
/// The layout is borrowed; the numbers are an agent's. An agent has no payables
/// or stock, so the tiles track what they actually own: cash still to collect,
/// cash in hand not yet banked, work outstanding, and what they've earned.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _togglingAvailability = false;
  bool _togglingAttendance = false;

  DashboardRepo get _repo => ref.read(dashboardRepoProvider);

  Future<void> _refresh() async {
    ref.invalidate(agentProfileProvider);
    ref.invalidate(agentPerformanceProvider);
    ref.invalidate(agentEarningsProvider);
    ref.invalidate(agentAttendanceProvider);
    ref.invalidate(assignedCollectionsProvider);
    ref.invalidate(assignedDeliveriesProvider);
    ref.invalidate(verificationTasksProvider);
    ref.invalidate(cashSummaryProvider);
    ref.invalidate(recentHistoryProvider);
    await Future.wait([
      ref.read(agentProfileProvider.future).then((_) {}, onError: (_) {}),
      ref.read(agentEarningsProvider.future).then((_) {}, onError: (_) {}),
      ref.read(recentHistoryProvider.future).then((_) {}, onError: (_) {}),
    ]);
  }

  Future<void> _toggleAvailable(bool value) async {
    if (_togglingAvailability) return;
    setState(() => _togglingAvailability = true);
    try {
      await _repo.setAvailable(value);
      ref.invalidate(agentProfileProvider);
    } catch (e) {
      if (mounted) showApiError(context, e, fallback: 'Could not update status.');
    } finally {
      if (mounted) setState(() => _togglingAvailability = false);
    }
  }

  Future<void> _checkIn() async {
    if (_togglingAttendance) return;
    setState(() => _togglingAttendance = true);
    try {
      await _repo.checkIn();
      ref.invalidate(agentAttendanceProvider);
      if (mounted) showToast(context, 'Checked in — shift started');
    } catch (e) {
      if (mounted) showApiError(context, e, fallback: 'Could not check in.');
    } finally {
      if (mounted) setState(() => _togglingAttendance = false);
    }
  }

  Future<void> _checkOut() async {
    if (_togglingAttendance) return;
    setState(() => _togglingAttendance = true);
    try {
      await _repo.checkOut();
      ref.invalidate(agentAttendanceProvider);
      if (mounted) showToast(context, 'Checked out — shift ended');
    } catch (e) {
      if (mounted) showApiError(context, e, fallback: 'Could not check out.');
    } finally {
      if (mounted) setState(() => _togglingAttendance = false);
    }
  }

  void _goTab(int i) => ref.read(homeTabProvider.notifier).state = i;

  void _open(Widget screen) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => screen),
      );

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(agentProfileProvider).valueOrNull;
    final attendance = ref.watch(agentAttendanceProvider).valueOrNull;

    // Keeps dispatch's view of this agent's location fresh whenever they're
    // available, not just while on an active task. Syncs on every profile
    // load (covers a relaunch while already on-duty), not just the toggle
    // tap itself — see PresenceController.
    ref.listen(agentProfileProvider, (_, next) {
      final isAvailable = next.valueOrNull?.isAvailable ?? false;
      final presence = ref.read(presenceControllerProvider);
      if (isAvailable) {
        presence.start();
      } else {
        presence.stop();
      }
    });

    return Scaffold(
      backgroundColor: AgentColors.bg,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            RefreshIndicator(
              color: AgentColors.brand,
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                // Bottom padding clears the pinned action bar so the last feed
                // row can always be scrolled out from under it.
                padding: const EdgeInsets.only(bottom: 104),
                children: [
                  _Header(
                    name: profile?.displayName ?? 'Agent',
                    code: profile?.code ?? '',
                    available: profile?.isAvailable ?? false,
                    busy: _togglingAvailability,
                    onToggle: _toggleAvailable,
                  ),
                  // Always visible (not just before check-in) — this used to
                  // disappear the moment an agent checked in, leaving no way
                  // to see shift status or check out short of Profile →
                  // Attendance. Now it tracks all three states.
                  if (attendance != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                      child: _ShiftStatusBar(
                        attendance: attendance,
                        busy: _togglingAttendance,
                        onCheckIn: _checkIn,
                        onCheckOut: _checkOut,
                      ),
                    ),
                  const SizedBox(height: 16),
                  _tiles(),
                  const SizedBox(height: 24),
                  _pendingTasks(),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: _ActionBar(
                onCollect: () => _goTab(1),
                onCash: () => _open(const CashScreen()),
                onDeliver: () => _goTab(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── The tile grid ──
  Widget _tiles() {
    final collections =
        ref.watch(assignedCollectionsProvider).valueOrNull ?? const [];
    final deliveries =
        ref.watch(assignedDeliveriesProvider).valueOrNull ?? const [];
    final verifications =
        ref.watch(verificationTasksProvider).valueOrNull ?? const [];
    final returnPickups =
        ref.watch(assignedReturnPickupsProvider).valueOrNull ?? const [];
    final cash = ref.watch(cashSummaryProvider).valueOrNull;
    final earnings = ref.watch(agentEarningsProvider).valueOrNull;
    // A monthly/salaried agent isn't paid per task, so what they earned isn't
    // a figure that means anything to them — hide it and default them onto
    // their task list instead (the tile grid below already leads there).
    final isMonthly =
        ref.watch(agentProfileProvider).valueOrNull?.isMonthlyEmployee ?? false;

    // Outstanding across every collection still on the agent's list — the
    // figure that answers "how much am I out to recover today?". This is money
    // NOT yet collected, so it must never read as money the agent is holding.
    final toCollect =
        collections.fold<double>(0, (sum, c) => sum + c.remaining);
    final pendingWork = collections.length +
        deliveries.length +
        verifications.length +
        returnPickups.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(children: [
            Expanded(
              // "Yet to Collect", not "To Collect", and amber rather than
              // green: this is money still with customers. Rendered green
              // beside the red In Hand tile it read as cash already recovered,
              // which is exactly the confusion agents reported.
              child: _MoneyTile(
                amount: toCollect,
                label: 'Yet to Collect',
                icon: Icons.south_rounded,
                tone: _TileTone.amber,
                onTap: () => _goTab(1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MoneyTile(
                amount: cash?.inHand ?? 0,
                label: 'Cash in Hand',
                icon: Icons.north_rounded,
                tone: _TileTone.red,
                onTap: () => _open(const CashScreen()),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: _InfoTile(
                title: '${deliveries.length}',
                subtitle: 'Deliveries pending',
                onTap: () => _goTab(2),
              ),
            ),
            if (!isMonthly) ...[
              const SizedBox(width: 12),
              Expanded(
                child: _InfoTile(
                  title: agentMoney(earnings?.total ?? 0),
                  subtitle: 'Earned today',
                  // Was wrongly opening PerformanceScreen — an "earnings"
                  // tile should land on the earnings breakdown.
                  onTap: () => _open(const EarningsScreen()),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: _InfoTile(
                title: 'Tasks',
                subtitle: pendingWork == 0
                    ? 'Nothing pending'
                    : '$pendingWork still open',
                onTap: () => _goTab(3),
              ),
            ),
            const SizedBox(width: 12),
            // Return pickups are a distinct job from a delivery (the agent
            // INSPECTS goods and decides at the door), so they get their own
            // entry point rather than hiding inside the deliveries list.
            Expanded(
              child: _InfoTile(
                title: '${returnPickups.length}',
                subtitle: 'Return pickups',
                onTap: () => _open(const ReturnPickupsScreen()),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            // Performance had no Home-level entry point at all — only
            // reachable via Profile. History still is (the "HISTORY" button
            // on the pending-tasks header below, plus Profile), so it isn't
            // losing its only path by giving up this tile slot.
            Expanded(
              child: _InfoTile(
                title: 'Performance',
                subtitle: 'Ratings & completed work',
                onTap: () => _open(const PerformanceScreen()),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  // ── Pending tasks — the home screen shows the TARGET, not the trophy ──
  //
  // This slot used to be "Recent activity": a feed of already-finished work,
  // front and centre. An agent opening the app needs what's NEXT — every open
  // delivery step, cash to confirm, collection to make, verification to run —
  // one tap from action. History still lives behind its tile.
  Widget _pendingTasks() {
    final deliveries =
        ref.watch(assignedDeliveriesProvider).valueOrNull ?? const [];
    final collections =
        ref.watch(assignedCollectionsProvider).valueOrNull ?? const [];
    final verifications =
        ref.watch(verificationTasksProvider).valueOrNull ?? const [];
    final returnPickups =
        ref.watch(assignedReturnPickupsProvider).valueOrNull ?? const [];

    final rows = <Widget>[];
    for (final d in deliveries) {
      rows.add(_PendingCard(
        icon: Icons.local_shipping_outlined,
        title: d.orderCode.isNotEmpty ? d.orderCode : d.customerName,
        subtitle: '${d.customerName} · ${_deliveryNextAction(d)}',
        trailing: agentMoney(d.amount),
        urgent: d.status == 'failed' ||
            (d.status == 'delivered' && d.paymentStatus != 'paid'),
        onTap: () => _open(DeliveryDetailScreen(
            id: d.id, orderCode: d.orderCode)),
      ));
    }
    for (final c in collections) {
      if (c.remaining <= 0) continue;
      rows.add(_PendingCard(
        icon: Icons.currency_rupee_rounded,
        title: c.customerName,
        subtitle: 'Collect payment · ${c.status}',
        trailing: agentMoney(c.remaining),
        urgent: c.isPriority || c.escalated,
        onTap: () => _open(CollectionDetailScreen(
            id: c.id, customerName: c.customerName)),
      ));
    }
    for (final r in returnPickups) {
      rows.add(_PendingCard(
        icon: Icons.assignment_return_outlined,
        title: r.returnCode.isNotEmpty ? r.returnCode : r.customerName,
        subtitle: '${r.customerName} · Return pickup',
        trailing: agentMoney(r.refundAmount),
        urgent: r.attemptNo > 1,
        onTap: () => _open(ReturnPickupDetailScreen(id: r.id)),
      ));
    }
    for (final v in verifications) {
      rows.add(_PendingCard(
        icon: Icons.fact_check_outlined,
        title: v.customerName,
        subtitle: 'Field verification · ${v.type}',
        trailing: '',
        urgent: false,
        onTap: () => _open(VerificationDetailScreen(
            id: v.id, customerName: v.customerName)),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  rows.isEmpty
                      ? 'Pending tasks'
                      : 'Pending tasks (${rows.length})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AgentColors.textPrimary,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _open(const HistoryScreen()),
                child: const Text('HISTORY',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: AppCard(
              child: Row(children: [
                Icon(Icons.task_alt_rounded,
                    size: 18, color: AgentColors.brand),
                SizedBox(width: 10),
                Expanded(
                  child: Text('All clear — nothing pending right now.',
                      style: TextStyle(color: AgentColors.textSecondary)),
                ),
              ]),
            ),
          )
        else
          ...[
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: row,
              ),
          ],
      ],
    );
  }

  /// The single next thing to do on this delivery, in the rider's words.
  String _deliveryNextAction(AgentDelivery d) => switch (d.status) {
        'assigned' => 'Accept the job',
        'accepted' => 'Pick up from store',
        'picked_up' => 'Start delivery',
        'out_for_delivery' => 'Deliver — open live map',
        'reached' => 'Handover: OTP + photo',
        'failed' => 'Return items to store',
        'return_initiated' => 'Hand over at the store',
        'delivered' => 'Collect cash',
        _ => d.status,
      };
}

// ═══════════════════════ components ═══════════════════════

/// `amber` = money still out with customers (not yours yet), `red` = physical
/// cash you are holding and owe a hand-over for, `green` = settled.
enum _TileTone { green, amber, red }

/// A money headline with a direction arrow — the two figures an agent is
/// personally accountable for.
class _MoneyTile extends StatelessWidget {
  const _MoneyTile({
    required this.amount,
    required this.label,
    required this.icon,
    required this.tone,
    required this.onTap,
  });

  final num amount;
  final String label;
  final IconData icon;
  final _TileTone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = switch (tone) {
      _TileTone.green => (AgentColors.brand, const Color(0xFFEAF7EF)),
      _TileTone.amber => (AgentColors.amber, const Color(0xFFFFF6E5)),
      _TileTone.red => (AgentColors.danger, const Color(0xFFFDECEC)),
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: fg.withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    agentMoney(amount),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: AgentColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  // Flexible so a long label (or a large system text scale)
                  // ellipsizes inside the tile instead of overflowing it.
                  Row(children: [
                    Flexible(
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: fg)),
                    ),
                    const SizedBox(width: 2),
                    Icon(icon, size: 14, color: fg),
                  ]),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AgentColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// A neutral tile: a headline value and what it means.
class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F6FF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AgentColors.border.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AgentColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AgentColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AgentColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.onCollect,
    required this.onCash,
    required this.onDeliver,
  });

  final VoidCallback onCollect;
  final VoidCallback onCash;
  final VoidCallback onDeliver;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _BarButton(
              label: 'Collect Cash',
              background: AgentColors.navy,
              onTap: onCollect,
            ),
          ),
          const SizedBox(width: 10),
          // Hand over cash — the one thing an agent CREATES from this screen.
          // Used to be a bare "+" circle with no text, so new agents had no
          // way to know what it did without tapping it first.
          Material(
            color: AgentColors.brandBright,
            borderRadius: BorderRadius.circular(999),
            elevation: 3,
            child: InkWell(
              onTap: onCash,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 5),
                    Text('Cash',
                        style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _BarButton(
              label: 'Deliveries',
              background: AgentColors.blue,
              onTap: onDeliver,
            ),
          ),
        ],
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.label,
    required this.background,
    required this.onTap,
  });

  final String label;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(999),
      elevation: 3,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({
    required this.name,
    required this.code,
    required this.available,
    required this.busy,
    required this.onToggle,
  });

  final String name;
  final String code;
  final bool available;
  final bool busy;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initial = (name.isNotEmpty ? name[0] : 'A').toUpperCase();
    return Container(
      color: AgentColors.bg,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFFE9EDFF),
            child: Text(initial,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: AgentColors.brand)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AgentColors.brand)),
                if (code.isNotEmpty)
                  Text(code,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.6,
                          color: AgentColors.label)),
              ],
            ),
          ),
          _AvailabilityPill(
              available: available, busy: busy, onToggle: onToggle),
          const SizedBox(width: 6),
          // Support used to be reachable only via Profile → Help & Support —
          // no help was ever more than one tab away, but three taps deep.
          // Home is always one tap from any tab, so this puts it at two.
          IconButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const SupportScreen())),
            icon: const Icon(Icons.help_outline_rounded,
                color: AgentColors.textSecondary),
            tooltip: 'Help & Support',
            visualDensity: VisualDensity.compact,
          ),
          const NotificationBell(),
        ],
      ),
    );
  }
}

class _AvailabilityPill extends StatelessWidget {
  const _AvailabilityPill(
      {required this.available, required this.busy, required this.onToggle});
  final bool available;
  final bool busy;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final color = available ? AgentColors.brand : AgentColors.textSecondary;
    return InkWell(
      onTap: busy ? null : () => onToggle(!available),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: (available ? const Color(0x337FFC97) : const Color(0x11000000)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                  width: 10,
                  height: 10,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else
              Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(available ? 'Online' : 'Offline',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      ),
    );
  }
}

/// Shift status, always visible on Home — not just the pre-check-in prompt it
/// used to be. Tracks all three states: not checked in, on duty (with a
/// one-tap check-out), and shift complete.
class _ShiftStatusBar extends StatelessWidget {
  const _ShiftStatusBar({
    required this.attendance,
    required this.busy,
    required this.onCheckIn,
    required this.onCheckOut,
  });

  final AgentAttendance attendance;
  final bool busy;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;

  String _time(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m ${dt.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    if (!attendance.checkedIn) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AgentColors.brandBright.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AgentColors.brand.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.wb_sunny_rounded, color: AgentColors.brand),
                SizedBox(width: 10),
                Expanded(
                  child: Text('Check in to start your shift',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AgentColors.textPrimary)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SlideToConfirm(
              label: 'Slide to check in',
              color: AgentColors.brand,
              icon: Icons.login_rounded,
              busy: busy,
              onConfirmed: onCheckIn,
            ),
          ],
        ),
      );
    }
    if (!attendance.checkedOut) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AgentColors.navy.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AgentColors.navy.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.timer_rounded, color: AgentColors.navy),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('On duty since ${_time(attendance.checkInAt)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AgentColors.textPrimary)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SlideToConfirm(
              label: 'Slide to check out',
              color: AgentColors.navy,
              icon: Icons.logout_rounded,
              busy: busy,
              onConfirmed: onCheckOut,
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AgentColors.divider.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.check_circle_rounded, color: AgentColors.brand, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text('Shift complete for today.',
                style: TextStyle(color: AgentColors.textSecondary)),
          ),
        ],
      ),
    );
  }
}

/// One actionable row on the home queue: what it is, the next step, the money,
/// and a tap straight into the doing.
class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.urgent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String trailing;
  final bool urgent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AppCard(
      child: Row(
        children: [
          Container(
            height: 38,
            width: 38,
            decoration: BoxDecoration(
              color: (urgent ? AgentColors.danger : AgentColors.brand)
                  .withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon,
                size: 19,
                color: urgent ? AgentColors.danger : AgentColors.brand),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color: urgent
                            ? AgentColors.danger
                            : AgentColors.textSecondary,
                        fontWeight:
                            urgent ? FontWeight.w600 : FontWeight.w400)),
              ],
            ),
          ),
          if (trailing.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(trailing,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13)),
          ],
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded,
              size: 20, color: AgentColors.textSecondary),
        ],
      ),
      ),
    );
  }
}
