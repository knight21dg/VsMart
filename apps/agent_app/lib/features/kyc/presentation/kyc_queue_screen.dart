import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ui.dart';
import '../data/kyc_data.dart';
import 'kyc_detail_screen.dart';
import 'kyc_providers.dart';

/// Body-only KYC review queue (pending applications the agent can review),
/// rendered inside the Verify tab's "KYC Review" sub-tab — no Scaffold/AppBar of
/// its own.
class KycQueueBody extends ConsumerWidget {
  const KycQueueBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(kycQueueProvider);
    return async.when(
        loading: () => const Loading(),
        error: (_, __) => ErrorRetry(
          message: 'Could not load the KYC queue.',
          onRetry: () => ref.invalidate(kycQueueProvider),
        ),
        data: (apps) {
          if (apps.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(kycQueueProvider),
              child: ListView(
                children: const [
                  SizedBox(height: 120),
                  EmptyState(
                    icon: Icons.verified_user_outlined,
                    title: 'No pending KYC applications',
                    message: 'New applications will appear here for review.',
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(kycQueueProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: apps.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _KycCard(app: apps[i]),
            ),
          );
        },
    );
  }
}

class _KycCard extends StatelessWidget {
  const _KycCard({required this.app});
  final KycApplicationModel app;

  @override
  Widget build(BuildContext context) {
    final docTypes = app.documents
        .map((d) => kycLabel(d.type))
        .where((s) => s.isNotEmpty)
        .toList();
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => KycDetailScreen(app: app)),
      ),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                LeadingIcon(
                    icon: Icons.assignment_ind_rounded,
                    color: kycStatusColor(app.status)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('KYC Application',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(
                        app.submittedAt.isNotEmpty
                            ? 'Submitted ${kycDate(app.submittedAt)}'
                            : 'Not yet submitted',
                        style: const TextStyle(
                            fontSize: 12, color: AgentColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                StatusPill(
                  label: kycStatusLabel(app.status),
                  color: kycStatusColor(app.status),
                ),
              ],
            ),
            if (docTypes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in docTypes)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AgentColors.bg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AgentColors.border),
                      ),
                      child: Text(t,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── shared display helpers ──

/// Human label for a step / document type key.
String kycLabel(String key) {
  switch (key) {
    case 'aadhaar':
      return 'Aadhaar';
    case 'pan':
      return 'PAN';
    case 'selfie':
      return 'Selfie';
    case 'residence':
      return 'Residence';
    case 'credit':
      return 'Credit';
    default:
      return key.isEmpty ? '' : key[0].toUpperCase() + key.substring(1);
  }
}

/// Human label for a review status value.
String kycStatusLabel(String status) {
  switch (status) {
    case 'pending':
      return 'Pending';
    case 'in_review':
      return 'In review';
    case 'approved':
      return 'Approved';
    case 'verified':
      return 'Verified';
    case 'rejected':
      return 'Rejected';
    case 'not_started':
      return 'Not started';
    default:
      return status.isEmpty ? 'Unknown' : status;
  }
}

/// Brand color for a review status value.
Color kycStatusColor(String status) {
  switch (status) {
    case 'approved':
    case 'verified':
      return AgentColors.green;
    case 'rejected':
      return AgentColors.danger;
    case 'in_review':
    case 'pending':
      return AgentColors.amber;
    default:
      return AgentColors.textSecondary;
  }
}

/// Best-effort YYYY-MM-DD from an ISO timestamp; falls back to the raw value.
String kycDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  final local = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}
