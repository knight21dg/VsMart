import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/ui.dart';

/// Help & Support — contact channels and a self-serve FAQ. Static content
/// (no backend); tapping a contact copies it to the clipboard.
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  static const _supportPhone = '1800-266-9111';
  static const _supportEmail = 'agents@thevsmart.com';

  static const _faqs = <(String, String)>[
    (
      'How do I check in for my shift?',
      'Open Home and tap "Check in" on the shift banner, or go to Profile → '
          'Attendance and use the check-in button.'
    ),
    (
      'A delivery/collection is not showing up',
      'Pull down to refresh the list. New assignments arrive as notifications; '
          'if it still is missing, contact your store manager.'
    ),
    (
      'What if the customer is not available?',
      'For deliveries use "Mark failed / reattempt". For collections, record a '
          'partial or raise a dispute from the task detail screen.'
    ),
    (
      'How is my earning calculated?',
      'Base pay plus incentives for completed tasks. See Profile → Earnings & '
          'Incentives for the full breakdown.'
    ),
    (
      'The app cannot get my location',
      'Enable location/GPS and grant the permission when prompted. Delivery '
          'arrival and photo proof need an accurate GPS fix.'
    ),
  ];

  void _copy(BuildContext context, String value, String what) {
    Clipboard.setData(ClipboardData(text: value));
    showToast(context, '$what copied');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgentColors.bg,
      appBar: AppBar(title: const Text('Help & Support')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SectionHeader('Contact us'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _ContactRow(
                  icon: Icons.call_rounded,
                  color: AgentColors.brand,
                  label: 'Call support',
                  value: _supportPhone,
                  onTap: () => _copy(context, _supportPhone, 'Number'),
                ),
                const Divider(height: 1, color: AgentColors.divider),
                _ContactRow(
                  icon: Icons.mail_outline_rounded,
                  color: AgentColors.blue,
                  label: 'Email support',
                  value: _supportEmail,
                  onTap: () => _copy(context, _supportEmail, 'Email'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionHeader('Frequently asked'),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < _faqs.length; i++) ...[
                  if (i > 0) const Divider(height: 1, color: AgentColors.divider),
                  _FaqTile(question: _faqs[i].$1, answer: _faqs[i].$2),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: LeadingIcon(icon: icon, color: color),
      title: Text(label,
          style: const TextStyle(
              fontWeight: FontWeight.w600, color: AgentColors.textPrimary)),
      subtitle: Text(value,
          style: const TextStyle(color: AgentColors.textSecondary)),
      trailing: const Icon(Icons.copy_rounded,
          size: 18, color: AgentColors.textSecondary),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.question, required this.answer});
  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        iconColor: AgentColors.brand,
        collapsedIconColor: AgentColors.textSecondary,
        title: Text(question,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AgentColors.textPrimary)),
        children: [
          Text(answer,
              style: const TextStyle(
                  color: AgentColors.textSecondary, height: 1.4)),
        ],
      ),
    );
  }
}
