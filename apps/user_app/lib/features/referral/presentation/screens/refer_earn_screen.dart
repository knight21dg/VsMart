import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../data/referral_data.dart';
import '../providers/referral_providers.dart';

/// The messaging channels the "Share Via" row can hand the invite off to.
enum _ShareChannel { whatsapp, telegram, facebook, sms }

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

  /// Canonical signup link carrying the referral code — used by channels that
  /// share a URL (Facebook, Telegram) rather than free text.
  String _shareLink(ReferralInfo info) =>
      'https://thevsmart.com/?ref=${info.code}';

  void _copyCode(BuildContext context, String code) {
    Clipboard.setData(ClipboardData(text: code));
    context.showSnack(context.l10n.referralCodeCopied);
  }

  /// Generic share via the OS share sheet (share_plus). Falls back to copying
  /// the invite to the clipboard if the sheet can't be shown.
  Future<void> _share(BuildContext context, ReferralInfo info) async {
    try {
      await SharePlus.instance.share(ShareParams(text: _shareMessage(info)));
    } catch (_) {
      if (context.mounted) _copyInviteFallback(context, info);
    }
  }

  /// Opens a specific messaging channel pre-filled with the invite. Falls back
  /// to copying the invite + a snackbar when the channel app isn't installed or
  /// the launch fails.
  Future<void> _shareVia(
    BuildContext context,
    ReferralInfo info,
    _ShareChannel channel,
  ) async {
    final msg = Uri.encodeComponent(_shareMessage(info));
    final link = Uri.encodeComponent(_shareLink(info));
    final uri = switch (channel) {
      _ShareChannel.whatsapp => Uri.parse('https://wa.me/?text=$msg'),
      _ShareChannel.telegram =>
        Uri.parse('https://t.me/share/url?url=$link&text=$msg'),
      // The Facebook sharer ignores custom text, so we hand it the link only.
      _ShareChannel.facebook =>
        Uri.parse('https://www.facebook.com/sharer/sharer.php?u=$link'),
      _ShareChannel.sms => Uri.parse('sms:?body=$msg'),
    };
    var launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!launched && context.mounted) {
      _copyInviteFallback(context, info);
    }
  }

  void _copyInviteFallback(BuildContext context, ReferralInfo info) {
    Clipboard.setData(ClipboardData(text: _shareMessage(info)));
    context.showSnack(context.l10n.referralInviteCopied);
  }

  Future<void> _applyCode(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.referralEnterCode),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(hintText: ctx.l10n.referralCodeHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(ctx.l10n.commonApply),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;
    final result = await ref.read(referralDataSourceProvider).applyCode(code);
    if (!context.mounted) return;
    context.showSnack(
      result.ok ? context.l10n.referralCodeApplied : result.message,
      isError: !result.ok,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final referral = ref.watch(referralProvider);

    return Scaffold(
      appBar: VSAppBar(title: context.l10n.profileReferEarn),
      body: SafeArea(
        top: false,
        child: referral.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => VSErrorView(
            message: context.l10n.commonSomethingWentWrong,
            onRetry: () => ref.invalidate(referralProvider),
          ),
          data: (info) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(referralProvider);
              await ref.read(referralProvider.future);
            },
            child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
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
              _ShareViaCard(
                onChannel: (channel) => _shareVia(context, info, channel),
              ),
              AppSpacing.vGapLg,
              _HowItWorksCard(reward: info.reward),
              AppSpacing.vGapXl,
              VSButton(
                label: context.l10n.referralInviteFriendsNow,
                icon: Icons.person_add_alt_1_rounded,
                onPressed: () => _share(context, info),
              ),
              AppSpacing.vGapMd,
              VSOutlinedButton(
                label: context.l10n.referralHaveCode,
                icon: Icons.redeem_rounded,
                onPressed: () => _applyCode(context, ref),
              ),
              AppSpacing.vGapMd,
              Center(
                child: Text(
                  context.l10n.referralTermsApply,
                  style: AppTypography.bodySmall
                      .copyWith(color: context.vsColors.textSecondary),
                ),
              ),
            ],
            ),
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
            context.l10n.referralInviteFriends,
            style: AppTypography.headlineLarge.copyWith(color: AppColors.white),
          ),
          AppSpacing.vGapXs,
          Text(
            context.l10n.referralEarnPerReferral(
                '₹${info.reward.toStringAsFixed(0)}'),
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
                      ? context.l10n.referralNoneYet
                      : context.l10n.referralSuccessfulCount(
                          info.referredCount),
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
            context.l10n.referralYourCode,
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
                  label: context.l10n.offersCopy,
                  icon: Icons.copy_rounded,
                  onPressed: onCopy,
                ),
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: VSButton(
                  label: context.l10n.commonShare,
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
  const _ShareViaCard({required this.onChannel});

  final void Function(_ShareChannel channel) onChannel;

  static const List<
      ({IconData icon, String label, Color color, _ShareChannel channel})>
      _channels = [
    (
      icon: Icons.chat_rounded,
      label: 'WhatsApp',
      color: AppColors.success,
      channel: _ShareChannel.whatsapp,
    ),
    (
      icon: Icons.send_rounded,
      label: 'Telegram',
      color: AppColors.trustBlue,
      channel: _ShareChannel.telegram,
    ),
    (
      icon: Icons.facebook_rounded,
      label: 'Facebook',
      color: AppColors.info,
      channel: _ShareChannel.facebook,
    ),
    (
      icon: Icons.sms_rounded,
      label: 'SMS',
      color: AppColors.offerOrange,
      channel: _ShareChannel.sms,
    ),
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
          Text(context.l10n.commonShareVia, style: AppTypography.titleLarge),
          AppSpacing.vGapLg,
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (final c in _channels)
                _ShareChannelTile(
                  icon: c.icon,
                  label: c.label,
                  color: c.color,
                  onTap: () => onChannel(c.channel),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShareChannelTile extends StatelessWidget {
  const _ShareChannelTile({
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
        title: context.l10n.referralInviteFriends,
        body: context.l10n.referralStepShareBody,
      ),
      (
        icon: Icons.how_to_reg_rounded,
        title: context.l10n.referralFriendRegisters,
        body: context.l10n.referralStepRegisterBody,
      ),
      (
        icon: Icons.shopping_bag_outlined,
        title: context.l10n.referralFirstOrder,
        body: context.l10n.referralStepOrderBody,
      ),
      (
        icon: Icons.account_balance_wallet_outlined,
        title: context.l10n.referralYouEarn,
        body: context.l10n.referralStepEarnBody(
            '₹${reward.toStringAsFixed(0)}'),
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
          Text(context.l10n.referralHowItWorks, style: AppTypography.titleLarge),
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
