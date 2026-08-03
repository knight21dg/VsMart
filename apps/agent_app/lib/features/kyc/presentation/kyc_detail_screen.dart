import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth_image.dart';
import '../../../core/providers.dart';
import '../../../core/ui.dart';
import '../data/kyc_data.dart';
import 'kyc_providers.dart';
import 'kyc_queue_screen.dart' show kycLabel, kycStatusLabel, kycStatusColor, kycDate;

/// Detail review of one KYC application: documents (with masked numbers) and
/// per-step Approve / Reject actions that call `POST /agent/kyc/<id>/review`.
class KycDetailScreen extends ConsumerStatefulWidget {
  const KycDetailScreen({super.key, required this.app});
  final KycApplicationModel app;

  @override
  ConsumerState<KycDetailScreen> createState() => _KycDetailScreenState();
}

class _KycDetailScreenState extends ConsumerState<KycDetailScreen> {
  /// step key currently being submitted (disables that row), null when idle.
  String? _busyStep;

  // Held in State (not read straight from widget.app) and replaced with the
  // backend's response after every review — otherwise a successful review
  // call had no visible effect: the step's StatusPill kept reading "Pending"
  // and its Approve/Reject buttons stayed fully enabled, because nothing
  // ever re-read the (correct, already-updated) server state. There's no
  // separate GET-by-id endpoint to refetch from — the review response
  // itself already carries the fresh application, so use that directly.
  late KycApplicationModel _app = widget.app;

  KycApplicationModel get app => _app;

  Future<void> _review(String step, String decision) async {
    if (!app.hasId || _busyStep != null) return;
    setState(() => _busyStep = step);
    try {
      final updated = await ref.read(kycRepoProvider).review(
            id: app.id!,
            step: step,
            decision: decision,
          );
      // Also refresh the OTHER screen's queue list (a fully-decided
      // application should drop out of "pending").
      ref.invalidate(kycQueueProvider);
      if (!mounted) return;
      setState(() => _app = updated);
      final verb = decision == 'approve' ? 'approved' : 'rejected';
      showToast(context, '${kycLabel(step)} $verb');
    } catch (e) {
      if (mounted) showApiError(context, e, fallback: 'Could not submit review');
    } finally {
      if (mounted) setState(() => _busyStep = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review Application')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── header ──
          AppCard(
            child: Row(
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
                              fontSize: 16, fontWeight: FontWeight.w700)),
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
          ),
          if (!app.hasId) ...[
            const SizedBox(height: 12),
            AppCard(
              child: Row(
                children: const [
                  Icon(Icons.info_outline, color: AgentColors.amber),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Review unavailable — this application has no id.',
                      style: TextStyle(color: AgentColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── documents ──
          const SizedBox(height: 20),
          const _SectionTitle('Documents'),
          const SizedBox(height: 8),
          if (app.documents.isEmpty)
            const AppCard(
              child: Text('No documents submitted.',
                  style: TextStyle(color: AgentColors.textSecondary)),
            )
          else
            for (final doc in app.documents) ...[
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(kycLabel(doc.type),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Text(
                                doc.numberMasked.isNotEmpty
                                    ? doc.numberMasked
                                    : 'No number on file',
                                style: const TextStyle(
                                    color: AgentColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        StatusPill(
                          label: kycStatusLabel(doc.status),
                          color: kycStatusColor(doc.status),
                        ),
                      ],
                    ),
                    // Show the actual document image (auth-gated) so the agent
                    // can visually verify it, not just the masked number.
                    if (doc.hasFile) ...[
                      const SizedBox(height: 10),
                      AuthImage(api: ref.read(apiProvider), path: doc.filePath),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

          // ── steps with per-step actions ──
          const SizedBox(height: 8),
          const _SectionTitle('Verification steps'),
          const SizedBox(height: 8),
          if (app.steps.isEmpty)
            const AppCard(
              child: Text('No verification steps.',
                  style: TextStyle(color: AgentColors.textSecondary)),
            )
          else
            for (final step in app.steps) ...[
              _StepCard(
                // A step already decided (approved/rejected) shouldn't keep
                // showing live action buttons — its StatusPill above is the
                // record now.
                step: step,
                enabled: app.hasId &&
                    step.status != 'approved' &&
                    step.status != 'rejected',
                busy: _busyStep == step.step,
                onApprove: () => _review(step.step, 'approve'),
                onReject: () => _review(step.step, 'reject'),
              ),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.enabled,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final KycStep step;
  final bool enabled;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(kycLabel(step.step),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              StatusPill(
                label: kycStatusLabel(step.status),
                color: kycStatusColor(step.status),
              ),
            ],
          ),
          if (step.note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(step.note,
                style: const TextStyle(color: AgentColors.textSecondary)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (enabled && !busy) ? onReject : null,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AgentColors.danger,
                    side: const BorderSide(color: AgentColors.danger),
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: (enabled && !busy) ? onApprove : null,
                  icon: busy
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Icon(Icons.check, size: 18),
                  label: const Text('Approve'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AgentColors.green,
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: AgentColors.label),
      );
}
