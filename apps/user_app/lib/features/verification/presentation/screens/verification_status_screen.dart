import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/app_error_presenter.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/l10n/status_labels.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/providers/session_provider.dart';
import '../../domain/entities/verification_application.dart';
import '../../domain/entities/verification_enums.dart';
import '../providers/verification_providers.dart';
import '../widgets/review_widgets.dart';

/// Tracks the submitted application: a status banner, progress timeline, and
/// state-specific content (approved / rejected actions).
class VerificationStatusScreen extends ConsumerWidget {
  const VerificationStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Sync the backend decision into the session so route guards release the
    // user (approved → full access; rejected → reapply).
    ref.listen(verificationStatusProvider, (_, next) {
      next.whenData((app) => _syncSession(ref, app.status));
    });
    final statusAsync = ref.watch(verificationStatusProvider);
    return Scaffold(
      appBar: VSAppBar(title: context.l10n.kycVerificationStatus),
      body: statusAsync.when(
        loading: () => const VSLoadingView(),
        error: (e, _) => VSErrorView(
          failure: e is Failure ? e : null,
          onRetry: () => ref.invalidate(verificationStatusProvider),
        ),
        data: (app) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(verificationStatusProvider);
            await ref.read(verificationStatusProvider.future);
          },
          child: _StatusBody(app: app),
        ),
      ),
    );
  }

  void _syncSession(WidgetRef ref, VerificationStatus status) {
    final user = ref.read(sessionControllerProvider).user;
    if (user == null) return;
    final session = ref.read(sessionControllerProvider.notifier);
    final analytics = ref.read(analyticsServiceProvider);
    if (status == VerificationStatus.approved &&
        user.kycStatus != KycStatus.verified) {
      session.setUser(
          user.copyWith(kycStatus: KycStatus.verified, creditEnabled: true));
      analytics.applicationApproved();
    } else if (status == VerificationStatus.rejected &&
        user.kycStatus != KycStatus.rejected) {
      session.setUser(user.copyWith(kycStatus: KycStatus.rejected));
      analytics.applicationRejected();
    }
  }
}

class _StatusBody extends StatelessWidget {
  const _StatusBody({required this.app});

  final VerificationApplication app;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: AppSpacing.screen,
      children: [
        _Banner(status: app.status),
        AppSpacing.vGapLg,
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: AppRadius.brLg,
            border: Border.all(color: context.vsColors.border),
          ),
          child: VSStatusTimeline(steps: _timeline(context, app)),
        ),
        AppSpacing.vGapLg,
        _Meta(app: app),
        AppSpacing.vGapLg,
        if (app.status == VerificationStatus.approved)
          _ApprovedCard(approvedLimit: app.approvedLimit ?? 5000)
        else if (app.status == VerificationStatus.rejected)
          _RejectedCard(reason: app.rejectionReason)
        else
          const _PendingNote(),
      ],
    );
  }

  List<VSTimelineStep> _timeline(
      BuildContext context, VerificationApplication app) {
    final l10n = context.l10n;
    VSTimelineState reviewState;
    VSTimelineState decisionState;
    switch (app.status) {
      case VerificationStatus.approved:
      case VerificationStatus.rejected:
        reviewState = VSTimelineState.done;
        decisionState = VSTimelineState.done;
      case VerificationStatus.underReview:
        reviewState = VSTimelineState.current;
        decisionState = VSTimelineState.pending;
      default:
        reviewState = VSTimelineState.pending;
        decisionState = VSTimelineState.pending;
    }
    return [
      VSTimelineStep(
        title: l10n.verificationApplicationSubmitted,
        subtitle: l10n.verifyAppReceived,
        state: VSTimelineState.done,
      ),
      VSTimelineStep(
        title: l10n.verifyStatusUnderReview,
        subtitle: l10n.verifyTeamVerifying,
        state: reviewState,
      ),
      VSTimelineStep(
        title: app.status == VerificationStatus.rejected
            ? 'Decision: Rejected'
            : 'Decision',
        subtitle: l10n.verificationCreditDecision,
        state: decisionState,
      ),
    ];
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.status});

  final VerificationStatus status;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final title = status.labelL10n(context.l10n);
    final (color, bg, icon, subtitle) = switch (status) {
      VerificationStatus.approved => (
          vs.success,
          vs.successTint,
          Icons.verified_rounded,
          'Your VS Credit is now active.'
        ),
      VerificationStatus.rejected => (
          vs.danger,
          vs.dangerTint,
          Icons.cancel_rounded,
          'Unfortunately we could not approve your application.'
        ),
      VerificationStatus.underReview => (
          vs.trust,
          vs.trustTint,
          Icons.hourglass_top_rounded,
          'Hang tight — this usually takes 1–2 days.'
        ),
      _ => (
          vs.warning,
          AppColors.amberTint,
          Icons.schedule_rounded,
          'Your application is queued for review.'
        ),
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.brLg),
      child: Row(
        children: [
          Container(
            height: 44,
            width: 44,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: AppColors.white),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTypography.titleLarge.copyWith(color: color)),
                Text(subtitle,
                    style: AppTypography.bodySmall
                        .copyWith(color: vs.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.app});

  final VerificationApplication app;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Row(
      children: [
        Expanded(
          child: Text(context.l10n.verificationApplicationRef(app.applicationId),
              style: AppTypography.labelMedium),
        ),
        Text(DateFormat('d MMM yyyy').format(app.submittedAt),
            style: AppTypography.bodySmall.copyWith(color: vs.textSecondary)),
      ],
    );
  }
}

class _PendingNote extends StatelessWidget {
  const _PendingNote();

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
          Icon(Icons.lightbulb_outline_rounded, size: 18, color: vs.trust),
          AppSpacing.hGapMd,
          Expanded(
            child: Text(
              context.l10n.verificationNotifyDecision,
              style:
                  AppTypography.bodySmall.copyWith(color: vs.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovedCard extends StatelessWidget {
  const _ApprovedCard({required this.approvedLimit});

  final num approvedLimit;

  @override
  Widget build(BuildContext context) {
    final faint = AppColors.white.withValues(alpha: 0.85);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: const BoxDecoration(
        gradient: AppColors.creditGradient,
        borderRadius: AppRadius.brXl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.verifyApprovedLimit,
              style: AppTypography.bodyMedium.copyWith(color: faint)),
          AppSpacing.vGapXs,
          Text(approvedLimit.asCurrency,
              style:
                  AppTypography.displayMedium.copyWith(color: AppColors.white)),
          AppSpacing.vGapXs,
          Text(context.l10n.verifyAvailableNow,
              style: AppTypography.bodySmall.copyWith(color: faint)),
          AppSpacing.vGapMd,
          SizedBox(
            width: double.infinity,
            child: Builder(
              builder: (context) => FilledButton(
                onPressed: () => context.goNamed(RouteNames.home),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.white,
                  foregroundColor: AppColors.vsGreen,
                  shape: const RoundedRectangleBorder(
                      borderRadius: AppRadius.brMd),
                  padding:
                      const EdgeInsets.symmetric(vertical: AppSpacing.md),
                ),
                child: Text(context.l10n.homeShopNow,
                    style: AppTypography.labelLarge
                        .copyWith(color: AppColors.vsGreen)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RejectedCard extends ConsumerStatefulWidget {
  const _RejectedCard({this.reason});

  final String? reason;

  @override
  ConsumerState<_RejectedCard> createState() => _RejectedCardState();
}

class _RejectedCardState extends ConsumerState<_RejectedCard> {
  bool _retrying = false;

  /// Re-open the rejected application on the backend, then drop the user back at
  /// the start of the SAME guided flow the dashboard uses (Aadhaar → PAN →
  /// selfie → residence → credit → review) for a fresh attempt — one reapply
  /// door, so uploads and residence are collected again before resubmit.
  Future<void> _reapply() async {
    setState(() => _retrying = true);
    final result = await ref.read(verificationRepositoryProvider).retry();
    if (!mounted) return;
    setState(() => _retrying = false);
    result.fold(
      (failure) => presentFailure(context, ref, failure),
      (_) {
        ref.invalidate(verificationStatusProvider);
        context.goNamed(RouteNames.aadhaarVerification);
      },
    );
  }

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
          Text(context.l10n.verifyReason, style: AppTypography.titleMedium),
          AppSpacing.vGapSm,
          Text(
            widget.reason ??
                'Your application did not meet the current eligibility criteria.',
            style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
          ),
          AppSpacing.vGapLg,
          Row(
            children: [
              Expanded(
                child: VSButton(
                  label: context.l10n.verifyReapply,
                  isLoading: _retrying,
                  onPressed: _reapply,
                ),
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: VSOutlinedButton(
                  label: context.l10n.supportContactUs,
                  onPressed: () => context.pushNamed(RouteNames.support),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
