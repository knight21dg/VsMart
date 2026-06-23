import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../data/support_data.dart';
import '../providers/support_providers.dart';

/// Support ticket history (loaded from the backend `/support/tickets`): status
/// summary cards, filter chips, and ticket cards. Tapping opens the thread.
class TicketHistoryScreen extends ConsumerStatefulWidget {
  const TicketHistoryScreen({super.key});

  @override
  ConsumerState<TicketHistoryScreen> createState() =>
      _TicketHistoryScreenState();
}

/// Lifecycle states a support ticket can be in, mapped to a [VSStatusChip] tone.
enum _TicketStatus {
  open('Open', VSStatusTone.info),
  inProgress('In Progress', VSStatusTone.info),
  resolved('Resolved', VSStatusTone.success),
  closed('Closed', VSStatusTone.neutral);

  const _TicketStatus(this.label, this.tone);

  final String label;
  final VSStatusTone tone;
}

/// Filter tabs shown above the list. [all] matches everything.
enum _TicketFilter {
  all('All', null),
  open('Open', _TicketStatus.open),
  inProgress('In Progress', _TicketStatus.inProgress),
  resolved('Resolved', _TicketStatus.resolved),
  closed('Closed', _TicketStatus.closed);

  const _TicketFilter(this.label, this.status);

  final String label;
  final _TicketStatus? status;
}

_TicketStatus _statusOf(SupportTicket t) => switch (t.status) {
      'in_progress' => _TicketStatus.inProgress,
      'resolved' => _TicketStatus.resolved,
      'closed' => _TicketStatus.closed,
      _ => _TicketStatus.open,
    };

String _updatedLabel(SupportTicket t) {
  const months = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  final d = t.createdAt;
  return 'Created ${d.day} ${months[d.month]} ${d.year}';
}

class _TicketHistoryScreenState extends ConsumerState<TicketHistoryScreen> {
  _TicketFilter _filter = _TicketFilter.all;

  @override
  Widget build(BuildContext context) {
    final ticketsAsync = ref.watch(ticketsProvider);
    return Scaffold(
      appBar: const VSAppBar(title: 'My Tickets'),
      body: SafeArea(
        top: false,
        child: ticketsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
            child: Text(
              "Couldn't load your tickets.",
              style: AppTypography.bodyMedium
                  .copyWith(color: context.vsColors.textSecondary),
            ),
          ),
          data: (tickets) {
            int countFor(_TicketStatus s) =>
                tickets.where((t) => _statusOf(t) == s).length;
            final filtered = _filter == _TicketFilter.all
                ? tickets
                : tickets.where((t) => _statusOf(t) == _filter.status).toList();
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(ticketsProvider),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl,
                ),
                children: [
                  _SummaryRow(
                    open: countFor(_TicketStatus.open),
                    inProgress: countFor(_TicketStatus.inProgress),
                    resolved: countFor(_TicketStatus.resolved),
                  ),
                  AppSpacing.vGapLg,
                  _FilterChips(
                    selected: _filter,
                    onSelected: (f) => setState(() => _filter = f),
                  ),
                  AppSpacing.vGapLg,
                  if (filtered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: AppSpacing.xxxl),
                      child: VSEmptyState(
                        icon: Icons.confirmation_number_outlined,
                        title: 'No tickets here',
                        message: 'You have no tickets in this category yet.',
                      ),
                    )
                  else
                    for (var i = 0; i < filtered.length; i++) ...[
                      if (i != 0) AppSpacing.vGapMd,
                      _TicketCard(
                        ticket: filtered[i],
                        onTap: () => context.pushNamed(
                          RouteNames.ticketDetails,
                          extra: filtered[i].id,
                        ),
                      ),
                    ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Three status summary cards (Open / In Progress / Resolved) — horizontally
/// scrollable so they never overflow on narrow screens.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.open,
    required this.inProgress,
    required this.resolved,
  });

  final int open;
  final int inProgress;
  final int resolved;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _SummaryCard(
            icon: Icons.error_outline_rounded,
            label: 'Open',
            count: open,
            tone: context.vsColors.trust,
          ),
          AppSpacing.hGapMd,
          _SummaryCard(
            icon: Icons.hourglass_bottom_rounded,
            label: 'In Progress',
            count: inProgress,
            tone: context.vsColors.offer,
          ),
          AppSpacing.hGapMd,
          _SummaryCard(
            icon: Icons.check_circle_outline_rounded,
            label: 'Resolved',
            count: resolved,
            tone: context.vsColors.success,
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.count,
    required this.tone,
  });

  final IconData icon;
  final String label;
  final int count;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      width: 148,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: tone),
              AppSpacing.hGapSm,
              Flexible(
                child: Text(
                  label,
                  style: AppTypography.labelMedium.copyWith(color: tone),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Text('$count', style: AppTypography.headlineMedium),
        ],
      ),
    );
  }
}

/// Scrollable filter tabs; the selected chip is brand-tinted.
class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onSelected});

  final _TicketFilter selected;
  final ValueChanged<_TicketFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _TicketFilter.values.length,
        separatorBuilder: (_, __) => AppSpacing.hGapSm,
        itemBuilder: (context, i) {
          final filter = _TicketFilter.values[i];
          final isSelected = filter == selected;
          return GestureDetector(
            onTap: () => onSelected(filter),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              decoration: BoxDecoration(
                color: isSelected ? vs.brand : context.colors.surface,
                borderRadius: AppRadius.brPill,
                border: Border.all(
                  color: isSelected ? vs.brand : vs.border,
                ),
              ),
              child: Text(
                filter.label,
                style: AppTypography.labelMedium.copyWith(
                  color: isSelected ? AppColors.white : context.colors.onSurface,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket, required this.onTap});

  final SupportTicket ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final status = _statusOf(ticket);
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brLg,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: AppRadius.brLg,
          border: Border.all(color: vs.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '#${ticket.id}',
                    style: AppTypography.labelMedium
                        .copyWith(color: vs.textSecondary),
                  ),
                ),
                if (ticket.priority == 'high') ...[
                  const VSStatusChip(
                    label: 'High Priority',
                    tone: VSStatusTone.danger,
                    dense: true,
                  ),
                  AppSpacing.hGapSm,
                ],
                VSStatusChip(
                  label: status.label,
                  tone: status.tone,
                  dense: true,
                ),
              ],
            ),
            AppSpacing.vGapSm,
            Text(ticket.subject, style: AppTypography.titleMedium),
            AppSpacing.vGapXs,
            Text(
              ticket.category,
              style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            AppSpacing.vGapMd,
            Row(
              children: [
                Icon(Icons.schedule_rounded,
                    size: 14, color: vs.textSecondary),
                AppSpacing.hGapSm,
                Expanded(
                  child: Text(
                    _updatedLabel(ticket),
                    style: AppTypography.bodySmall
                        .copyWith(color: vs.textSecondary),
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 20, color: vs.textSecondary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
