import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../verification/domain/entities/verification_enums.dart';
import '../../../verification/presentation/providers/verification_providers.dart';

/// KYC verification hub: overall progress, the step checklist, the credit
/// benefits unlocked on completion, and an entry point into the flow.
///
/// Progress is derived from the real KYC application (`GET /kyc/status` via
/// [verificationStatusProvider]) — not hardcoded.
class KycDashboardScreen extends ConsumerWidget {
  const KycDashboardScreen({super.key});

  static const _docSteps = <_KycStep>[
    _KycStep('Aadhaar Verification', route: RouteNames.aadhaarVerification),
    _KycStep('PAN Verification', route: RouteNames.panVerification),
    _KycStep('Live Selfie', route: RouteNames.selfieVerification),
    _KycStep('Residence Verification', route: RouteNames.residenceVerification),
    _KycStep('Credit Application', route: RouteNames.creditApplication),
  ];

  /// Doc steps are complete once the application has been submitted and not
  /// rejected (pending / under review / approved).
  bool _docsDone(VerificationStatus s) =>
      s == VerificationStatus.pending ||
      s == VerificationStatus.underReview ||
      s == VerificationStatus.approved;

  List<_KycStep> _steps(VerificationStatus s) {
    final docDone = _docsDone(s);
    return [
      const _KycStep('Mobile Verified', done: true),
      const _KycStep('Address Added', done: true),
      for (final step in _docSteps) step.copyWith(done: docDone),
    ];
  }

  void _startNext(BuildContext context, List<_KycStep> steps) {
    final next = steps.firstWhere(
      (s) => !s.done && s.route != null,
      orElse: () => const _KycStep(''),
    );
    if (next.route != null) context.pushNamed(next.route!);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(verificationStatusProvider);

    return Scaffold(
      appBar: const VSAppBar(title: 'KYC Verification'),
      body: SafeArea(
        child: statusAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => VSErrorView(
            message: "Couldn't load your verification status.",
            onRetry: () => ref.invalidate(verificationStatusProvider),
          ),
          data: (app) => _Body(
            status: app.status,
            rejectionReason: app.rejectionReason,
            steps: _steps(app.status),
            onStart: (steps) => _startNext(context, steps),
            onTapStep: (s) {
              if (!s.done && s.route != null) context.pushNamed(s.route!);
            },
            onViewStatus: () =>
                context.pushNamed(RouteNames.verificationStatus),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.status,
    required this.rejectionReason,
    required this.steps,
    required this.onStart,
    required this.onTapStep,
    required this.onViewStatus,
  });

  final VerificationStatus status;
  final String? rejectionReason;
  final List<_KycStep> steps;
  final ValueChanged<List<_KycStep>> onStart;
  final ValueChanged<_KycStep> onTapStep;
  final VoidCallback onViewStatus;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final completed = steps.where((s) => s.done).length;
    final progress = completed / steps.length;
    final submitted = status.isSubmitted;

    final (ctaLabel, ctaAction) = switch (status) {
      VerificationStatus.approved ||
      VerificationStatus.pending ||
      VerificationStatus.underReview =>
        ('View Status', onViewStatus),
      VerificationStatus.rejected => ('Re-submit Documents', () => onStart(steps)),
      _ => ('Start Verification', () => onStart(steps)),
    };

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: AppSpacing.screen,
            children: [
              Text(
                'Complete verification to unlock VS Credit benefits.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
              ),
              AppSpacing.vGapLg,
              _StatusCard(
                progress: progress,
                completed: completed,
                total: steps.length,
                status: status,
                rejectionReason: rejectionReason,
              ),
              AppSpacing.vGapLg,
              _ChecklistCard(steps: steps, onTapStep: onTapStep),
              AppSpacing.vGapLg,
              const _BenefitsCard(),
              AppSpacing.vGapLg,
              const _SecurityNote(),
            ],
          ),
        ),
        Padding(
          padding: AppSpacing.screen,
          child: VSButton(
            label: ctaLabel,
            trailingIcon: submitted
                ? Icons.open_in_new_rounded
                : Icons.arrow_forward_rounded,
            onPressed: ctaAction,
          ),
        ),
      ],
    );
  }
}

class _KycStep {
  const _KycStep(this.label, {this.done = false, this.route});
  final String label;
  final bool done;
  final String? route;

  _KycStep copyWith({bool? done}) =>
      _KycStep(label, done: done ?? this.done, route: route);
}

({String label, VSStatusTone tone}) _statusChip(VerificationStatus s) =>
    switch (s) {
      VerificationStatus.approved => (label: 'Verified', tone: VSStatusTone.success),
      VerificationStatus.pending ||
      VerificationStatus.underReview =>
        (label: 'Under Review', tone: VSStatusTone.info),
      VerificationStatus.rejected => (label: 'Action Needed', tone: VSStatusTone.danger),
      _ => (label: 'Not Started', tone: VSStatusTone.neutral),
    };

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.progress,
    required this.completed,
    required this.total,
    required this.status,
    required this.rejectionReason,
  });

  final double progress;
  final int completed;
  final int total;
  final VerificationStatus status;
  final String? rejectionReason;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final chip = _statusChip(status);
    final ringColor = switch (status) {
      VerificationStatus.approved => vs.success,
      VerificationStatus.rejected => vs.danger,
      _ => vs.brand,
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brXl,
        border: Border.all(color: vs.border),
        boxShadow: AppShadows.xs,
      ),
      child: Column(
        children: [
          Text('Verification Status', style: AppTypography.headlineSmall),
          AppSpacing.vGapXs,
          VSStatusChip(label: chip.label, tone: chip.tone),
          AppSpacing.vGapXs,
          Text('$completed of $total Steps Completed',
              style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary)),
          AppSpacing.vGapLg,
          SizedBox(
            height: 130,
            width: 130,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: 130,
                  width: 130,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 10,
                    backgroundColor: vs.border,
                    valueColor: AlwaysStoppedAnimation(ringColor),
                    strokeCap: StrokeCap.round,
                  ),
                ),
                Text('${(progress * 100).round()}%',
                    style: AppTypography.displayMedium.copyWith(color: ringColor)),
              ],
            ),
          ),
          if (status == VerificationStatus.rejected &&
              (rejectionReason?.isNotEmpty ?? false)) ...[
            AppSpacing.vGapMd,
            Text(
              rejectionReason!,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(color: vs.danger),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChecklistCard extends StatelessWidget {
  const _ChecklistCard({required this.steps, required this.onTapStep});

  final List<_KycStep> steps;
  final ValueChanged<_KycStep> onTapStep;

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
          Text('CHECKLIST',
              style: AppTypography.labelSmall.copyWith(
                color: vs.textSecondary,
                letterSpacing: 1,
              )),
          AppSpacing.vGapMd,
          for (final step in steps)
            _ChecklistRow(step: step, onTap: () => onTapStep(step)),
        ],
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.step, required this.onTap});

  final _KycStep step;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      onTap: step.done ? null : onTap,
      borderRadius: AppRadius.brSm,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: step.done ? vs.brandTint.withValues(alpha: 0.4) : null,
          borderRadius: AppRadius.brSm,
        ),
        child: Row(
          children: [
            if (step.done)
              Icon(Icons.check_circle_rounded, color: vs.success, size: 24)
            else
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: vs.border, width: 1.5),
                ),
              ),
            AppSpacing.hGapMd,
            Expanded(
              child: Text(
                step.label,
                style: AppTypography.bodyLarge.copyWith(
                  color: step.done ? vs.textSecondary : null,
                  decoration: step.done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            if (!step.done && step.route != null)
              Icon(Icons.chevron_right_rounded, color: vs.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _BenefitsCard extends StatelessWidget {
  const _BenefitsCard();

  static const _benefits = [
    (Icons.credit_card_rounded, 'Credit Limit', 'On approval'),
    (Icons.calendar_month_rounded, 'Flexible Plans', 'Weekly / Monthly'),
    (Icons.local_offer_rounded, 'Exclusive Offers', 'Member Only'),
    (Icons.speed_rounded, 'VS Score', 'Build Credit'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: const BoxDecoration(
        gradient: AppColors.creditGradient,
        borderRadius: AppRadius.brXl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.star_border_rounded, color: AppColors.white),
              AppSpacing.hGapSm,
              Text('Unlock VS Credit Benefits',
                  style: AppTypography.titleLarge.copyWith(color: AppColors.white)),
            ],
          ),
          AppSpacing.vGapMd,
          Row(
            children: [
              for (var i = 0; i < 2; i++)
                Expanded(child: _BenefitTile(data: _benefits[i])),
            ],
          ),
          AppSpacing.vGapSm,
          Row(
            children: [
              for (var i = 2; i < 4; i++)
                Expanded(child: _BenefitTile(data: _benefits[i])),
            ],
          ),
        ],
      ),
    );
  }
}

class _BenefitTile extends StatelessWidget {
  const _BenefitTile({required this.data});

  final (IconData, String, String) data;

  @override
  Widget build(BuildContext context) {
    final (icon, title, subtitle) = data;
    return Container(
      margin: const EdgeInsets.all(AppSpacing.xs),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.15),
        borderRadius: AppRadius.brMd,
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.white, size: 18),
          AppSpacing.hGapSm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelMedium
                        .copyWith(color: AppColors.white)),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelSmall.copyWith(
                        color: AppColors.white.withValues(alpha: 0.8))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityNote extends StatelessWidget {
  const _SecurityNote();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: vs.trustTint,
        borderRadius: AppRadius.brMd,
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline_rounded, color: vs.trust, size: 20),
          AppSpacing.hGapMd,
          Expanded(
            child: Text(
              'Your information is encrypted and securely stored following bank-grade security standards.',
              style: AppTypography.bodySmall.copyWith(color: vs.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
