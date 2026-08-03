import 'package:flutter/material.dart';

import '../../../core/ui.dart';

/// Confirmation shown after a field verification is submitted — the closing step
/// of the document-verification flow.
class VerificationSubmittedScreen extends StatelessWidget {
  const VerificationSubmittedScreen({
    super.key,
    required this.customerName,
    this.decision,
  });

  final String customerName;
  final String? decision; // 'approve' | 'reject' | null (submitted for review)

  ({String label, Color color, IconData icon}) get _outcome {
    switch (decision) {
      case 'approve':
        return (label: 'Approved', color: AgentColors.brand, icon: Icons.verified_rounded);
      case 'reject':
        return (label: 'Rejected', color: AgentColors.danger, icon: Icons.cancel_rounded);
      default:
        return (
          label: 'Submitted for review',
          color: AgentColors.amber,
          icon: Icons.hourglass_bottom_rounded
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _outcome;
    return Scaffold(
      backgroundColor: AgentColors.bg,
      appBar: AppBar(title: const Text('Submitted')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                    color: o.color.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(o.icon, color: o.color, size: 44),
              ),
              const SizedBox(height: 12),
              const Text('Verification Submitted',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AgentColors.textPrimary)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                    color: o.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999)),
                child: Text(o.label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: o.color)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (customerName.isNotEmpty) ...[
                  Row(
                    children: [
                      LeadingIcon(icon: Icons.person_rounded, color: o.color),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(customerName,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                const Text(
                  'The store will finalise the KYC decision based on your field '
                  'verification. Thank you.',
                  style: TextStyle(color: AgentColors.textSecondary, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
