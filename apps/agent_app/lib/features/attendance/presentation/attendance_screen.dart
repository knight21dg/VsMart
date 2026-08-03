import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui.dart';
import '../../dashboard/data/dashboard_data.dart';
import '../../dashboard/presentation/dashboard_providers.dart';

/// Attendance & Check-In — today's shift status with check-in / check-out,
/// plus a calendar of this agent's attendance history so they can see their
/// own record instead of only ever seeing "today".
/// Backed by GET /agents/attendance/me + /agents/attendance/history and
/// POST check-in / check-out.
class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  bool _busy = false;
  late DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);

  String get _monthKey =>
      '${_visibleMonth.year.toString().padLeft(4, '0')}-${_visibleMonth.month.toString().padLeft(2, '0')}';

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _visibleMonth.year == now.year && _visibleMonth.month == now.month;
  }

  void _changeMonth(int delta) {
    setState(() => _visibleMonth =
        DateTime(_visibleMonth.year, _visibleMonth.month + delta));
  }

  Future<void> _act(Future<AgentAttendance> Function() call, String ok) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await call();
      ref.invalidate(agentAttendanceProvider);
      ref.invalidate(attendanceHistoryProvider(_monthKey));
      if (mounted) showToast(context, ok);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final att = ref.watch(agentAttendanceProvider);
    final repo = ref.read(dashboardRepoProvider);
    return Scaffold(
      backgroundColor: AgentColors.bg,
      appBar: AppBar(title: const Text('Attendance')),
      body: att.when(
        loading: () => const Loading(),
        error: (_, __) => ErrorRetry(
          message: "Couldn't load attendance.",
          onRetry: () => ref.invalidate(agentAttendanceProvider),
        ),
        data: (a) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(agentAttendanceProvider);
            ref.invalidate(attendanceHistoryProvider(_monthKey));
            await ref.read(agentAttendanceProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _StatusCard(attendance: a),
              const SizedBox(height: 20),
              if (!a.checkedIn)
                SlideToConfirm(
                  label: 'Slide to check in',
                  color: AgentColors.brand,
                  icon: Icons.login_rounded,
                  busy: _busy,
                  onConfirmed: () =>
                      _act(repo.checkIn, 'Checked in — shift started'),
                )
              else if (!a.checkedOut)
                SlideToConfirm(
                  label: 'Slide to check out',
                  color: AgentColors.navy,
                  icon: Icons.logout_rounded,
                  busy: _busy,
                  onConfirmed: () =>
                      _act(repo.checkOut, 'Checked out — shift ended'),
                )
              else
                const AppCard(
                  child: Row(children: [
                    Icon(Icons.check_circle_rounded,
                        color: AgentColors.brand, size: 20),
                    SizedBox(width: 10),
                    Text("Shift complete for today.",
                        style: TextStyle(color: AgentColors.textSecondary)),
                  ]),
                ),
              const SizedBox(height: 28),
              const SectionHeader('Your attendance'),
              const SizedBox(height: 8),
              _Calendar(
                month: _visibleMonth,
                isCurrentMonth: _isCurrentMonth,
                onPrev: () => _changeMonth(-1),
                onNext: _isCurrentMonth ? null : () => _changeMonth(1),
                historyAsync: ref.watch(attendanceHistoryProvider(_monthKey)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.attendance});
  final AgentAttendance attendance;

  String _time(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '—';
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m ${dt.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final onDuty = attendance.onDuty;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                attendance.date.isNotEmpty ? attendance.date : 'Today',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AgentColors.textPrimary),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (onDuty ? AgentColors.brand : AgentColors.textSecondary)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(onDuty ? 'On duty' : 'Off duty',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            onDuty ? AgentColors.brand : AgentColors.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: _TimeCol(
                  label: 'Checked in',
                  value: attendance.checkedIn
                      ? _time(attendance.checkInAt)
                      : '—'),
            ),
            Expanded(
              child: _TimeCol(
                  label: 'Checked out',
                  value: attendance.checkedOut
                      ? _time(attendance.checkOutAt)
                      : '—'),
            ),
          ]),
        ],
      ),
    );
  }
}

class _TimeCol extends StatelessWidget {
  const _TimeCol({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: AgentColors.textSecondary)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AgentColors.textPrimary)),
      ],
    );
  }
}

const _weekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// A month grid of this agent's attendance, colour-coded per day, with a tap
/// on any recorded day showing its check-in/out times and hours worked.
class _Calendar extends StatelessWidget {
  const _Calendar({
    required this.month,
    required this.isCurrentMonth,
    required this.onPrev,
    required this.onNext,
    required this.historyAsync,
  });

  final DateTime month;
  final bool isCurrentMonth;
  final VoidCallback onPrev;
  final VoidCallback? onNext;
  final AsyncValue<AttendanceHistory> historyAsync;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: onPrev,
                icon: const Icon(Icons.chevron_left_rounded),
                color: AgentColors.textSecondary,
              ),
              Text('${_monthNames[month.month - 1]} ${month.year}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
              IconButton(
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right_rounded),
                color: AgentColors.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: 4),
          historyAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text("Couldn't load attendance history.",
                  style: TextStyle(color: AgentColors.textSecondary)),
            ),
            data: (history) => _Grid(month: month, days: history.days),
          ),
          const SizedBox(height: 12),
          const _Legend(),
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.month, required this.days});
  final DateTime month;
  final List<AttendanceDay> days;

  @override
  Widget build(BuildContext context) {
    final byDay = {for (final d in days) d.date.day: d};
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    // Monday-start grid: weekday is 1 (Mon) .. 7 (Sun).
    final leadingBlanks = DateTime(month.year, month.month, 1).weekday - 1;
    final today = DateTime.now();
    final isCurrentMonth =
        month.year == today.year && month.month == today.month;

    return Column(
      children: [
        Row(
          children: [
            for (final w in _weekdayLabels)
              Expanded(
                child: Center(
                  child: Text(w,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AgentColors.textSecondary)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: leadingBlanks + daysInMonth,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
          ),
          itemBuilder: (context, i) {
            if (i < leadingBlanks) return const SizedBox.shrink();
            final dayNum = i - leadingBlanks + 1;
            final date = DateTime(month.year, month.month, dayNum);
            final isToday = isCurrentMonth && dayNum == today.day;
            final isFuture = date.isAfter(DateTime(today.year, today.month, today.day));
            final rec = byDay[dayNum];
            return _DayCell(
              day: dayNum,
              isToday: isToday,
              isFuture: isFuture,
              record: rec,
            );
          },
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isToday,
    required this.isFuture,
    required this.record,
  });

  final int day;
  final bool isToday;
  final bool isFuture;
  final AttendanceDay? record;

  Color? get _fill {
    if (record == null) return null;
    if (record!.checkedIn && record!.checkedOut) {
      return AgentColors.brand.withValues(alpha: 0.14);
    }
    if (record!.onDuty) return AgentColors.amber.withValues(alpha: 0.18);
    return AgentColors.textSecondary.withValues(alpha: 0.10);
  }

  Color get _dot {
    if (record == null) return Colors.transparent;
    if (record!.checkedIn && record!.checkedOut) return AgentColors.brand;
    if (record!.onDuty) return AgentColors.amber;
    return AgentColors.textSecondary;
  }

  void _showDetail(BuildContext context) {
    final r = record;
    if (r == null) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AgentColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${r.date.day}/${r.date.month}/${r.date.year}',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: _TimeCol(
                    label: 'Checked in',
                    value: r.checkedIn ? _fmt(r.checkInAt) : '—'),
              ),
              Expanded(
                child: _TimeCol(
                    label: 'Checked out',
                    value: r.checkedOut ? _fmt(r.checkOutAt) : '—'),
              ),
            ]),
            if (r.hoursWorked != null) ...[
              const SizedBox(height: 12),
              Text('${r.hoursWorked!.toStringAsFixed(1)} hours on duty',
                  style: const TextStyle(color: AgentColors.textSecondary)),
            ],
          ],
        ),
      ),
    );
  }

  String _fmt(String iso) {
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '—';
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m ${dt.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        onTap: record == null ? null : () => _showDetail(context),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: _fill,
            borderRadius: BorderRadius.circular(10),
            border: isToday
                ? Border.all(color: AgentColors.brand, width: 1.4)
                : null,
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$day',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                      color: isFuture
                          ? AgentColors.textSecondary.withValues(alpha: 0.4)
                          : AgentColors.textPrimary)),
              if (record != null) ...[
                const SizedBox(height: 2),
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(color: _dot, shape: BoxShape.circle),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: const [
        _LegendItem(color: AgentColors.brand, label: 'Full day'),
        _LegendItem(color: AgentColors.amber, label: 'On duty'),
        _LegendItem(color: AgentColors.textSecondary, label: 'No record'),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});
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
            style:
                const TextStyle(fontSize: 11.5, color: AgentColors.textSecondary)),
      ],
    );
  }
}
