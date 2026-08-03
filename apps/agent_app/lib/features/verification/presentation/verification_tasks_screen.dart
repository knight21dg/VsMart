import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui.dart';
import '../data/verification_data.dart';
import 'verification_detail_screen.dart';
import 'verification_providers.dart';

/// Human label for a verification status value.
String verificationStatusLabel(String status) {
  switch (status) {
    case 'pending':
      return 'Pending';
    case 'assigned':
      return 'Assigned';
    case 'in_progress':
      return 'In Progress';
    case 'submitted':
      return 'Submitted';
    case 'approved':
      return 'Approved';
    case 'rejected':
      return 'Rejected';
    default:
      return status.isEmpty
          ? 'Unknown'
          : status[0].toUpperCase() + status.substring(1).replaceAll('_', ' ');
  }
}

/// Brand color for a verification status value.
Color verificationStatusColor(String status) {
  switch (status) {
    case 'approved':
      return AgentColors.green;
    case 'rejected':
      return AgentColors.danger;
    case 'in_progress':
    case 'submitted':
      return AgentColors.brand;
    case 'pending':
    case 'assigned':
      return AgentColors.amber;
    default:
      return AgentColors.textSecondary;
  }
}

/// Human label for a verification task type.
String verificationTypeLabel(String type) {
  switch (type) {
    case 'kyc':
      return 'KYC';
    case 'residence':
      return 'Residence';
    case 'credit':
      return 'Credit';
    default:
      return type.isEmpty
          ? 'Verification'
          : type[0].toUpperCase() + type.substring(1);
  }
}

/// Lists the field-verification tasks assigned to / available for the agent.
class VerificationTasksScreen extends ConsumerWidget {
  const VerificationTasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(verificationTasksProvider);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(verificationTasksProvider.future),
      child: async.when(
        loading: () => const Loading(),
        error: (_, __) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.6,
              child: ErrorRetry(
                message: 'Could not load verification tasks.',
                onRetry: () => ref.invalidate(verificationTasksProvider),
              ),
            ),
          ],
        ),
        data: (tasks) {
          if (tasks.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: const EmptyState(
                    icon: Icons.fact_check_outlined,
                    title: 'No field tasks',
                    message: 'New verification visits will appear here.',
                  ),
                ),
              ],
            );
          }
          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: tasks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _TaskCard(task: tasks[i]),
          );
        },
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task});
  final VerificationTask task;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VerificationDetailScreen(
            id: task.id,
            customerName: task.customerName,
          ),
        ),
      ),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                LeadingIcon(
                    icon: Icons.verified_user_rounded,
                    color: verificationStatusColor(task.status)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    task.customerName.isNotEmpty
                        ? task.customerName
                        : 'Customer',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                StatusPill(
                  label: verificationStatusLabel(task.status),
                  color: verificationStatusColor(task.status),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _TypeBadge(type: task.type),
                const Spacer(),
                const Icon(Icons.chevron_right,
                    color: AgentColors.textSecondary),
              ],
            ),
            if (task.note.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                task.note,
                style: const TextStyle(color: AgentColors.textSecondary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AgentColors.brand.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        verificationTypeLabel(type),
        style: const TextStyle(
          color: AgentColors.brand,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
