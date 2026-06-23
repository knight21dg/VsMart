import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../data/referral_data.dart';
import '../providers/referral_providers.dart';

/// Refer & Earn — invite friends to VS Mart and earn wallet credit.
///
/// Backed by `GET /referrals` (the user's unique code, per-referral reward and
/// completed-referral count) and `POST /referrals/apply` (redeem a friend's code).
class ReferEarnScreen extends ConsumerWidget {
  const ReferEarnScreen({super.key});

  String _shareMessage(ReferralInfo info) =>
      'Shop groceries on VS Mart and get a welcome reward! Use my referral code '
      '${info.code} when you sign up. I earn ₹${info.reward.toStringAsFixed(0)} '
      'when you place your first order.';

  void _copyCode(BuildContext context, String code) {
    Clipboard.setData(ClipboardData(text: code));
    context.showSnack('Code copied');
  }

  void _share(BuildContext context, ReferralInfo info) {
    Clipboard.setData(ClipboardData(text: _shareMessage(info)));
    context.showSnack('Invite message copied — paste it to your friends');
  }

  Future<void> _applyCode(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter a referral code'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'e.g. VS00042'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;
    final result = await ref.read(referralDataSourceProvider).applyCode(code);
    if (!context.mounted) return;
    context.showSnack(result.message, isError: !result.ok);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final referral = ref.watch(referralProvider);

    return Scaffold(
      appBar: const VSAppBar(title: 'Refer & Earn'),
      body: SafeArea(
        top: false,
        child: referral.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => VSErrorView(
            message: "Couldn't load your referral details.",
            onRetry: () => ref.invalidate(referralProvider),
          ),
          data: (info) => ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            children: [
              _HeroCard(
                info: info,
                onCopy: () => _copyCode(context, info.code),
                onShare: () => _share(context, info),
              ),
              AppSpacing.vGapLg,
              _ShareViaCard(onTap: () => _share(context, info)),
              AppSpacing.vGapLg,
              _HowItWorksCard(reward: info.reward),
              AppSpacing.vGapXl,
              VSButton(
                label: 'Invite Friends Now',
                icon: Icons.person_add_alt_1_rounded,
                onPressed: () => _share(context, info),
              ),
              AppSpacing.vGapMd,
              VSOutlinedButton(
                label: 'Have a referral code?',
                icon: Icons.redeem_rounded,
                onPressed: () => _applyCode(context, ref),
              ),
              AppSpacing.vGapMd,
              Center(
                child: Text(
                  'Terms & Conditions Apply',
                  style: AppTypography.bodySmall
                      .copyWith(color: context.vsColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gradient hero: headline, reward line, referral count, illustration and the
/// inner referral-code card with Copy / Share buttons.
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.info,
    required this.onCopy,
    required this.onShare,
  });

  final ReferralInfo info;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: const BoxDecoration(
        gradient: AppColors.greenGradient,
        borderRadius: AppRadius.brXl,
      ),
      child: Column(
        children: [
          Text(
            'Invite Friends',
            style: AppTypography.headlineLarge.copyWith(color: AppColors.white),
          ),
          AppSpacing.vGapXs,
          Text(
            'Earn ₹${info.reward.toStringAsFixed(0)} Per Successful Referral',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.white.withValues(alpha: 0.9),
            ),
          ),
          AppSpacing.vGapMd,
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.18),
              borderRadius: AppRadius.brPill,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.celebration_outlined,
                  size: 16,
                  color: AppColors.white.withValues(alpha: 0.9),
                ),
                AppSpacing.hGapSm,
                Text(
                  info.referredCount == 0
                      ? 'No referrals yet — invite to start earning'
                      : '${info.referredCount} successful '
                          '${info.referredCount == 1 ? 'referral' : 'referrals'}',
                  style: AppTypography.labelMedium.copyWith(color: AppColors.white),
                ),
              ],
            ),
          ),
          AppSpacing.vGapLg,
          Container(
            height: 96,
            width: 96,
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.18),
              borderRadius: AppRadius.brXl,
            ),
            child: const Icon(
              Icons.phone_iphone_rounded,
              size: 48,
              color: AppColors.white,
            ),
          ),
          AppSpacing.vGapLg,
          _CodeCard(code: info.code, onCopy: onCopy, onShare: onShare),
        ],
      ),
    );
  }
}

/// Inner white card holding the referral code and the Copy / Share buttons.
class _CodeCard extends StatelessWidget {
  const _CodeCard({
    required this.code,
    required this.onCopy,
    required this.onShare,
  });

  final String code;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
      ),
      child: Column(
        children: [
          Text(
            'Your Referral Code',
            style: AppTypography.bodySmall.copyWith(color: vs.textSecondary),
          ),
          AppSpacing.vGapXs,
          Text(
            code.isEmpty ? '—' : code,
            style: AppTypography.headlineMedium.copyWith(
              color: vs.brand,
              letterSpacing: 2,
            ),
          ),
          AppSpacing.vGapMd,
          Row(
            children: [
              Expanded(
                child: VSOutlinedButton(
                  label: 'Copy',
                  icon: Icons.copy_rounded,
                  onPressed: onCopy,
                ),
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: VSButton(
                  label: 'Share',
                  icon: Icons.share_rounded,
                  onPressed: onShare,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Share Via" card with the four sharing channels.
class _ShareViaCard extends StatelessWidget {
  const _ShareViaCard({required this.onTap});

  final VoidCallback onTap;

  static const List<({IconData icon, String label, Color color})> _channels = [
    (icon: Icons.chat_rounded, label: 'WhatsApp', color: AppColors.success),
    (icon: Icons.send_rounded, label: 'Telegram', color: AppColors.trustBlue),
    (icon: Icons.facebook_rounded, label: 'Facebook', color: AppColors.info),
    (icon: Icons.sms_rounded, label: 'SMS', color: AppColors.offerOrange),
  ];

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Share Via', style: AppTypography.titleLarge),
          AppSpacing.vGapLg,
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (final c in _channels)
                _ShareChannel(
                  icon: c.icon,
                  label: c.label,
                  color: c.color,
                  onTap: onTap,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShareChannel extends StatelessWidget {
  const _ShareChannel({
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
      borderRadius: AppRadius.brMd,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 52,
              width: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 24, color: color),
            ),
            AppSpacing.vGapSm,
            Text(
              label,
              style: AppTypography.bodySmall.copyWith(color: vs.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// "How It Works" card with the four numbered referral steps.
class _HowItWorksCard extends StatelessWidget {
  const _HowItWorksCard({required this.reward});

  final num reward;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final steps = <({IconData icon, String title, String body})>[
      (
        icon: Icons.person_add_alt_1_rounded,
        title: 'Invite Friends',
        body: 'Share your unique link or code.',
      ),
      (
        icon: Icons.how_to_reg_rounded,
        title: 'Friend Registers',
        body: 'They sign up using your code.',
      ),
      (
        icon: Icons.shopping_bag_outlined,
        title: 'First Order',
        body: 'They place their first valid order.',
      ),
      (
        icon: Icons.account_balance_wallet_outlined,
        title: 'You Earn',
        body: 'Get ₹${reward.toStringAsFixed(0)} added to your wallet.',
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How It Works', style: AppTypography.titleLarge),
          AppSpacing.vGapLg,
          for (var i = 0; i < steps.length; i++) ...[
            if (i != 0) AppSpacing.vGapLg,
            _StepRow(
              icon: steps[i].icon,
              title: steps[i].title,
              body: steps[i].body,
            ),
          ],
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 40,
          width: 40,
          decoration: BoxDecoration(
            color: vs.brandTint,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: vs.brand),
        ),
        AppSpacing.hGapMd,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.titleMedium),
              AppSpacing.vGapXs,
              Text(
                body,
                style: AppTypography.bodySmall.copyWith(color: vs.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
