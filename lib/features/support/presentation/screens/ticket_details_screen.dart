import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../data/support_data.dart';
import '../providers/support_providers.dart';

const _months = [
  '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];
String _fmtDate(DateTime d) => '${d.day} ${_months[d.month]} ${d.year}';

/// Support ticket detail view (loaded from `/support/tickets/{code}`): header
/// (id, subject, status, created date), the issue description (first message),
/// and a status timeline. Tapping the CTA opens the conversation thread.
class TicketDetailsScreen extends ConsumerWidget {
  const TicketDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    final code = GoRouterState.of(context).extra as String?;
    if (code == null) {
      return const Scaffold(
        appBar: VSAppBar(title: 'Ticket Details'),
        body: Center(child: Text('Ticket not found.')),
      );
    }
    final ticketAsync = ref.watch(ticketProvider(code));
    return Scaffold(
      appBar: const VSAppBar(
        title: 'Ticket Details',
        actions: [Icon(Icons.more_vert_rounded)],
      ),
      body: SafeArea(
        top: false,
        child: ticketAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(
            child: Text(
              "Couldn't load this ticket.",
              style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
            ),
          ),
          data: (ticket) => ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xxl,
            ),
            children: [
              _HeaderCard(ticket: ticket),
              AppSpacing.vGapLg,
              _DescriptionCard(ticket: ticket),
              AppSpacing.vGapXl,
              _ProgressSection(status: ticket.status),
              AppSpacing.vGapXl,
              _ActionsRow(code: code),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _BottomBar(borderColor: vs.border, code: code),
    );
  }
}

// ---------------------------------------------------------------------------
// Header card
// ---------------------------------------------------------------------------

({String label, VSStatusTone tone}) _statusChip(String status) => switch (status) {
      'in_progress' => (label: 'In Progress', tone: VSStatusTone.info),
      'resolved' => (label: 'Resolved', tone: VSStatusTone.success),
      'closed' => (label: 'Closed', tone: VSStatusTone.neutral),
      _ => (label: 'Open', tone: VSStatusTone.info),
    };

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.ticket});

  final SupportTicket ticket;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final status = _statusChip(ticket.status);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('VS-TKT-${ticket.id}',
                        style: AppTypography.headlineSmall),
                    AppSpacing.vGapXs,
                    Text(
                      ticket.subject,
                      style: AppTypography.bodyLarge
                          .copyWith(color: vs.textSecondary),
                    ),
                  ],
                ),
              ),
              AppSpacing.hGapMd,
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (ticket.priority == 'high') ...[
                    const VSStatusChip(
                        label: 'High Priority', tone: VSStatusTone.danger),
                    AppSpacing.vGapSm,
                  ],
                  VSStatusChip(label: status.label, tone: status.tone),
                ],
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Divider(height: 1),
          ),
          Row(
            children: [
              Expanded(
                child: _MetaColumn(
                    label: 'Created', value: _fmtDate(ticket.createdAt)),
              ),
              Expanded(
                child: _MetaColumn(
                    label: 'Category', value: ticket.category),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaColumn extends StatelessWidget {
  const _MetaColumn({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(color: vs.textSecondary),
        ),
        AppSpacing.vGapXs,
        Text(value, style: AppTypography.titleMedium),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Description + attachments card
// ---------------------------------------------------------------------------

class _DescriptionCard extends StatelessWidget {
  const _DescriptionCard({required this.ticket});

  final SupportTicket ticket;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final description = ticket.messages.isNotEmpty
        ? ticket.messages.first.body
        : 'No description provided.';
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.description_outlined,
                  size: 18, color: vs.textSecondary),
              AppSpacing.hGapSm,
              Text('Issue Description', style: AppTypography.titleMedium),
            ],
          ),
          AppSpacing.vGapMd,
          Text(
            description,
            style: AppTypography.bodyMedium
                .copyWith(color: vs.textSecondary, height: 1.6),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ticket progress timeline (derived from status)
// ---------------------------------------------------------------------------

enum _StepState { done, active, pending }

class _ProgressSection extends StatelessWidget {
  const _ProgressSection({required this.status});

  final String status;

  List<_StepData> _stepsFor(String status) {
    // Position in the open → in_progress → resolved/closed flow.
    final reached = switch (status) {
      'in_progress' => 1,
      'resolved' || 'closed' => 2,
      _ => 0,
    };
    final labels = ['Ticket Created', 'Under Review', 'Resolved'];
    return [
      for (var i = 0; i < labels.length; i++)
        _StepData(
          title: labels[i],
          state: i < reached
              ? _StepState.done
              : (i == reached ? _StepState.active : _StepState.pending),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final steps = _stepsFor(status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.xs),
          child: Text('Ticket Progress', style: AppTypography.titleLarge),
        ),
        AppSpacing.vGapMd,
        for (var i = 0; i < steps.length; i++)
          _TimelineTile(data: steps[i], isLast: i == steps.length - 1),
      ],
    );
  }
}

class _StepData {
  const _StepData({required this.title, required this.state});

  final String title;
  final _StepState state;
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({required this.data, required this.isLast});

  final _StepData data;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;

    final isDone = data.state == _StepState.done;
    final isActive = data.state == _StepState.active;
    final accent = isDone ? vs.success : (isActive ? vs.trust : vs.border);

    final titleColor = data.state == _StepState.pending
        ? vs.textSecondary
        : (isActive ? vs.trust : context.colors.onSurface);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              _StepMarker(state: data.state, accent: accent),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: isDone ? vs.success : vs.border,
                  ),
                ),
            ],
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.title,
                    style: AppTypography.titleMedium.copyWith(color: titleColor),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepMarker extends StatelessWidget {
  const _StepMarker({required this.state, required this.accent});

  final _StepState state;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final surface = context.colors.surface;
    switch (state) {
      case _StepState.done:
        return Container(
          height: 24,
          width: 24,
          decoration: BoxDecoration(
            color: surface,
            shape: BoxShape.circle,
            border: Border.all(color: accent, width: 2),
          ),
          child: Icon(Icons.check_rounded, size: 14, color: accent),
        );
      case _StepState.active:
        return Container(
          height: 24,
          width: 24,
          decoration: BoxDecoration(
            color: surface,
            shape: BoxShape.circle,
            border: Border.all(color: accent, width: 2),
          ),
          child: Center(
            child: Container(
              height: 10,
              width: 10,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
          ),
        );
      case _StepState.pending:
        return Container(
          height: 24,
          width: 24,
          decoration: BoxDecoration(
            color: surface,
            shape: BoxShape.circle,
            border: Border.all(color: accent, width: 2),
          ),
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Quick action tiles
// ---------------------------------------------------------------------------

class _ActionsRow extends StatelessWidget {
  const _ActionsRow({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Row(
      children: [
        Expanded(
          child: _ActionTile(
            icon: Icons.reply_rounded,
            label: 'Add Reply',
            color: vs.trust,
            onTap: () =>
                context.pushNamed(RouteNames.supportChat, extra: code),
          ),
        ),
        AppSpacing.hGapMd,
        Expanded(
          child: _ActionTile(
            icon: Icons.attach_file_rounded,
            label: 'Upload File',
            color: vs.trust,
            onTap: () => context.showSnack('Upload a file to this ticket.'),
          ),
        ),
        AppSpacing.hGapMd,
        Expanded(
          child: _ActionTile(
            icon: Icons.call_rounded,
            label: 'Call Support',
            color: vs.trust,
            onTap: () => context.showSnack('Connecting you to support…'),
          ),
        ),
        AppSpacing.hGapMd,
        Expanded(
          child: _ActionTile(
            icon: Icons.cancel_outlined,
            label: 'Close Ticket',
            color: vs.danger,
            onTap: () => context.showSnack('Close this ticket?'),
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brLg,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: AppRadius.brLg,
          border: Border.all(color: vs.border),
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: color),
            AppSpacing.vGapSm,
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppTypography.labelSmall.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sticky bottom CTA
// ---------------------------------------------------------------------------

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.borderColor, required this.code});

  final Color borderColor;
  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: VSButton(
            label: 'Open Conversation',
            icon: Icons.chat_bubble_outline_rounded,
            onPressed: () =>
                context.pushNamed(RouteNames.supportChat, extra: code),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared card shell
// ---------------------------------------------------------------------------

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      width: double.infinity,
      padding: AppSpacing.card,
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
      ),
      child: child,
    );
  }
}
