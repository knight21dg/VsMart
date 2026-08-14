import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/ui.dart';
import '../../attendance/presentation/attendance_screen.dart';
import '../../dashboard/presentation/dashboard_providers.dart';
import '../../earnings/presentation/earnings_screen.dart';
import '../../history/history_screen.dart';
import '../../kyc/presentation/my_kyc_screen.dart';
import '../../performance/presentation/performance_screen.dart';
import '../../support/presentation/support_screen.dart';
import '../data/profile_data.dart';

/// The agent's account: identity, KYC status, and edit / log-out actions.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(userProfileProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: async.when(
        loading: () => const Loading(),
        error: (_, __) => ErrorRetry(
          message: "Couldn't load your profile.",
          onRetry: () => ref.invalidate(userProfileProvider),
        ),
        data: (profile) => _Body(profile: profile),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.profile});
  final UserProfile profile;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _saving = false;

  UserProfile get p => widget.profile;

  Future<void> _edit() async {
    final name = TextEditingController(text: p.name);
    final email = TextEditingController(text: p.email);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save')),
        ],
      ),
    );
    if (saved != true || _saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(profileRepoProvider)
          .update(name: name.text.trim(), email: email.text.trim());
      ref.invalidate(userProfileProvider);
      ref.invalidate(agentProfileProvider);
      if (mounted) showToast(context, 'Profile updated');
    } catch (e) {
      if (mounted) showApiError(context, e, fallback: 'Could not update profile.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need your OTP to sign back in.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AgentColors.danger),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Log out')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(authStatusProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final agent = ref.watch(agentProfileProvider).valueOrNull;
    final initial =
        (p.displayName.isNotEmpty ? p.displayName[0] : '?').toUpperCase();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── header ──
        AppCard(
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AgentColors.brand.withValues(alpha: 0.12),
                child: Text(initial,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AgentColors.brand)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.displayName,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    StatusPill(
                      label: p.role.isNotEmpty ? p.role.toUpperCase() : 'AGENT',
                      color: AgentColors.brand,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── details ──
        AppCard(
          child: Column(
            children: [
              _Row(label: 'Phone', value: p.phone.isNotEmpty ? p.phone : '—'),
              _Row(label: 'Email', value: p.email.isNotEmpty ? p.email : 'Not set'),
              if (agent?.code.isNotEmpty ?? false)
                _Row(label: 'Agent code', value: agent!.code),
              if (agent != null)
                _Row(
                    label: 'Status',
                    value: agent.isAvailable ? 'Online' : 'Offline'),
              _Row(
                label: 'KYC',
                value: p.kycStatus.isNotEmpty ? p.kycStatus : '—',
                last: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── menu ──
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              // The agent's OWN verification. The app only ever had the
              // reviewer queue for CUSTOMER applications, so an agent whose own
              // KYC was pending or rejected saw a status word on this screen and
              // had no way to act on it.
              _MenuRow(
                icon: Icons.verified_user_outlined,
                color: AgentColors.pink,
                label: 'My KYC',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const MyKycScreen())),
              ),
              const Divider(height: 1, color: AgentColors.divider),
              _MenuRow(
                icon: Icons.history_rounded,
                color: AgentColors.brandBright,
                label: 'Task history',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const HistoryScreen())),
              ),
              const Divider(height: 1, color: AgentColors.divider),
              // Salaried agents aren't paid per task, so a per-task/lifetime
              // earnings breakdown isn't a figure that means anything to them.
              if (agent?.isMonthlyEmployee != true) ...[
                _MenuRow(
                  icon: Icons.account_balance_wallet_rounded,
                  color: AgentColors.brand,
                  label: 'Earnings & Incentives',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const EarningsScreen())),
                ),
                const Divider(height: 1, color: AgentColors.divider),
              ],
              _MenuRow(
                icon: Icons.insights_rounded,
                color: AgentColors.blue,
                label: 'Performance',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const PerformanceScreen())),
              ),
              const Divider(height: 1, color: AgentColors.divider),
              _MenuRow(
                icon: Icons.event_available_rounded,
                color: AgentColors.amber,
                label: 'Attendance',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const AttendanceScreen())),
              ),
              const Divider(height: 1, color: AgentColors.divider),
              _MenuRow(
                icon: Icons.help_outline_rounded,
                color: AgentColors.navy,
                label: 'Help & Support',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const SupportScreen())),
              ),
              const Divider(height: 1, color: AgentColors.divider),
              _MenuRow(
                icon: Icons.info_outline_rounded,
                color: AgentColors.textSecondary,
                label: 'About',
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: 'VS Mart Partner',
                  applicationVersion: '1.0.0',
                  applicationLegalese: '© VS Mart',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        FilledButton.icon(
          onPressed: _saving ? null : _edit,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.edit_outlined),
          label: const Text('Edit profile'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _logout,
          style: OutlinedButton.styleFrom(
            foregroundColor: AgentColors.danger,
            minimumSize: const Size.fromHeight(50),
          ),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Log out'),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(label,
          style: const TextStyle(
              fontWeight: FontWeight.w600, color: AgentColors.textPrimary)),
      trailing: const Icon(Icons.chevron_right_rounded,
          color: AgentColors.textSecondary),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.last = false});
  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AgentColors.textSecondary)),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
