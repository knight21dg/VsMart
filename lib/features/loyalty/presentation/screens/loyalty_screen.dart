import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/widgets.dart';
import '../../data/loyalty_data.dart';
import '../providers/loyalty_providers.dart';

/// Reward-points home: balance hero, redeem CTA, and points history.
class LoyaltyScreen extends ConsumerWidget {
  const LoyaltyScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref
      ..invalidate(loyaltyStatusProvider)
      ..invalidate(loyaltyLedgerProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(loyaltyStatusProvider);
    return Scaffold(
      appBar: const VSAppBar(title: 'Rewards'),
      body: statusAsync.when(
        loading: () => const VSLoadingView(),
        error: (e, _) => VSErrorView(
          failure: e is Failure ? e : null,
          onRetry: () => ref.invalidate(loyaltyStatusProvider),
        ),
        data: (status) => RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: AppSpacing.screen,
            children: [
              _PointsHeroCard(status: status),
              AppSpacing.vGapLg,
              VSButton(
                label: 'Redeem Points',
                icon: Icons.redeem_rounded,
                variant: VSButtonVariant.secondary,
                onPressed: status.balance > 0
                    ? () => _openRedeemDialog(context, ref, status)
                    : null,
              ),
              AppSpacing.vGapXl,
              Text('History', style: AppTypography.titleLarge),
              AppSpacing.vGapMd,
              const _LedgerSection(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openRedeemDialog(
    BuildContext context,
    WidgetRef ref,
    LoyaltyStatus status,
  ) async {
    final controller = TextEditingController();
    final result = await showDialog<({bool ok, String message, num balance})>(
      context: context,
      builder: (_) =>
          _RedeemDialog(controller: controller, status: status, ref: ref),
    );
    controller.dispose();
    if (result == null || !context.mounted) return;
    context.showSnack(result.message, isError: !result.ok);
    if (result.ok) {
      ref
        ..invalidate(loyaltyStatusProvider)
        ..invalidate(loyaltyLedgerProvider);
    }
  }
}

/// Gradient hero showing the current balance, tier, and lifetime earnings.
class _PointsHeroCard extends StatelessWidget {
  const _PointsHeroCard({required this.status});

  final LoyaltyStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: const BoxDecoration(
        gradient: AppColors.creditGradient,
        borderRadius: AppRadius.brXl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Reward Points',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.white.withValues(alpha: 0.85),
                ),
              ),
              if (status.tier.isNotEmpty) _TierChip(tier: status.tier),
            ],
          ),
          AppSpacing.vGapMd,
          Text(
            Formatters.number(status.balance),
            style: AppTypography.displayMedium.copyWith(color: AppColors.white),
          ),
          Text(
            'points available',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.white.withValues(alpha: 0.85),
            ),
          ),
          AppSpacing.vGapLg,
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.15),
              borderRadius: AppRadius.brMd,
            ),
            child: Row(
              children: [
                const Icon(Icons.workspace_premium_outlined,
                    color: AppColors.white, size: 18),
                AppSpacing.hGapSm,
                Text(
                  'Lifetime earned: '
                  '${Formatters.number(status.lifetimeEarned)} pts',
                  style: AppTypography.labelMedium
                      .copyWith(color: AppColors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tier pill rendered on the hero (light-on-gradient).
class _TierChip extends StatelessWidget {
  const _TierChip({required this.tier});

  final String tier;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.2),
        borderRadius: AppRadius.brPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, color: AppColors.white, size: 14),
          const SizedBox(width: 4),
          Text(
            tier,
            style: AppTypography.labelSmall.copyWith(color: AppColors.white),
          ),
        ],
      ),
    );
  }
}

/// Watches the ledger separately so the history can load/error independently
/// of the balance hero.
class _LedgerSection extends ConsumerWidget {
  const _LedgerSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerAsync = ref.watch(loyaltyLedgerProvider);
    return ledgerAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.only(top: AppSpacing.xxl),
        child: VSLoadingView(),
      ),
      error: (e, _) => VSErrorView(
        failure: e is Failure ? e : null,
        onRetry: () => ref.invalidate(loyaltyLedgerProvider),
      ),
      data: (entries) {
        if (entries.isEmpty) {
          return const VSEmptyState(
            title: 'No points activity yet',
            message: 'Earn and redeem points to see your history here.',
            icon: Icons.history_rounded,
          );
        }
        return Column(
          children: [
            for (final entry in entries) ...[
              _LedgerRow(entry: entry),
              if (entry != entries.last) AppSpacing.vGapMd,
            ],
          ],
        );
      },
    );
  }
}

/// A single points-history row: type icon, note, date, signed points.
class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.entry});

  final PointsEntry entry;

  ({IconData icon, Color color, Color tint, String sign}) _style(
    BuildContext context,
  ) {
    final vs = context.vsColors;
    return switch (entry.type) {
      'earn' => (
          icon: Icons.add_circle_outline_rounded,
          color: vs.success,
          tint: vs.successTint,
          sign: '+',
        ),
      'redeem' => (
          icon: Icons.redeem_rounded,
          color: vs.trust,
          tint: vs.trustTint,
          sign: '',
        ),
      'expire' => (
          icon: Icons.schedule_rounded,
          color: vs.danger,
          tint: vs.dangerTint,
          sign: '',
        ),
      _ => (
          icon: Icons.swap_horiz_rounded,
          color: vs.textSecondary,
          tint: context.colors.surface,
          sign: entry.points >= 0 ? '+' : '',
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final s = _style(context);
    final note = entry.note.isNotEmpty ? entry.note : _label(entry.type);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
      ),
      child: Row(
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(color: s.tint, shape: BoxShape.circle),
            child: Icon(s.icon, color: s.color, size: 22),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(note, style: AppTypography.titleMedium),
                Text(
                  Formatters.dateTime(entry.date),
                  style: AppTypography.bodySmall
                      .copyWith(color: vs.textSecondary),
                ),
              ],
            ),
          ),
          AppSpacing.hGapSm,
          Text(
            '${s.sign}${Formatters.number(entry.points)}',
            style: AppTypography.titleMedium.copyWith(color: s.color),
          ),
        ],
      ),
    );
  }

  String _label(String type) => switch (type) {
        'earn' => 'Points earned',
        'redeem' => 'Points redeemed',
        'expire' => 'Points expired',
        _ => 'Points adjustment',
      };
}

/// Modal asking how many points to redeem; returns the redeem result.
class _RedeemDialog extends StatefulWidget {
  const _RedeemDialog({
    required this.controller,
    required this.status,
    required this.ref,
  });

  final TextEditingController controller;
  final LoyaltyStatus status;
  final WidgetRef ref;

  @override
  State<_RedeemDialog> createState() => _RedeemDialogState();
}

class _RedeemDialogState extends State<_RedeemDialog> {
  bool _submitting = false;
  String? _error;

  Future<void> _submit() async {
    final points = int.tryParse(widget.controller.text.trim());
    if (points == null || points <= 0) {
      setState(() => _error = 'Enter a valid number of points');
      return;
    }
    if (points > widget.status.balance) {
      setState(() => _error =
          'You only have ${Formatters.number(widget.status.balance)} points');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result =
        await widget.ref.read(loyaltyDataSourceProvider).redeem(points);
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return AlertDialog(
      title: const Text('Redeem Points'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You have ${Formatters.number(widget.status.balance)} points '
            'available.',
            style:
                AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
          ),
          AppSpacing.vGapLg,
          TextField(
            controller: widget.controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            enabled: !_submitting,
            decoration: InputDecoration(
              labelText: 'Points to redeem',
              hintText: 'e.g. 100',
              errorText: _error,
              prefixIcon: const Icon(Icons.stars_rounded),
            ),
          ),
        ],
      ),
      actions: [
        VSOutlinedButton(
          label: 'Cancel',
          isExpanded: false,
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        ),
        VSButton(
          label: 'Redeem',
          isExpanded: false,
          variant: VSButtonVariant.secondary,
          isLoading: _submitting,
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}
