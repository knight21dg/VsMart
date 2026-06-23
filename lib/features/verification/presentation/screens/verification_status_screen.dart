import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
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
      appBar: const VSAppBar(title: 'Verification Status'),
      body: statusAsync.when(
        loading: () => const VSLoadingView(),
        error: (e, _) => VSErrorView(
          failure: e is Failure ? e : null,
          onRetry: () => ref.invalidate(verificationStatusProvider),
        ),
        data: (app) => _StatusBody(app: app),
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
          child: VSStatusTimeline(steps: _timeline(app)),
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

  List<VSTimelineStep> _timeline(VerificationApplication app) {
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
      const VSTimelineStep(
        title: 'Application Submitted',
        subtitle: 'We received your application',
        state: VSTimelineState.done,
      ),
      VSTimelineStep(
        title: 'Under Review',
        subtitle: 'Our team is verifying your details',
        state: reviewState,
      ),
      VSTimelineStep(
        title: app.status == VerificationStatus.rejected
            ? 'Decision: Rejected'
            : 'Decision',
        subtitle: 'Credit eligibility decision',
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
    final (color, bg, icon, title, subtitle) = switch (status) {
      VerificationStatus.approved => (
          vs.success,
          vs.successTint,
          Icons.verified_rounded,
          'Approved',
          'Your VS Credit is now active.'
        ),
      VerificationStatus.rejected => (
          vs.danger,
          vs.dangerTint,
          Icons.cancel_rounded,
          'Rejected',
          'Unfortunately we could not approve your application.'
        ),
      VerificationStatus.underReview => (
          vs.trust,
          vs.trustTint,
          Icons.hourglass_top_rounded,
          'Under Review',
          'Hang tight — this usually takes 1–2 days.'
        ),
      _ => (
          vs.warning,
          AppColors.amberTint,
          Icons.schedule_rounded,
          'Pending',
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
          child: Text('Application ${app.applicationId}',
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
              "We'll notify you the moment a decision is made. You can keep "
              'browsing in the meantime.',
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
          Text('Approved Credit Limit',
              style: AppTypography.bodyMedium.copyWith(color: faint)),
          AppSpacing.vGapXs,
          Text(approvedLimit.asCurrency,
              style:
                  AppTypography.displayMedium.copyWith(color: AppColors.white)),
          AppSpacing.vGapXs,
          Text('Available now', style: AppTypography.bodySmall.copyWith(color: faint)),
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
                child: Text('Start Shopping',
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

class _RejectedCard extends StatelessWidget {
  const _RejectedCard({this.reason});

  final String? reason;

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
          Text('Reason', style: AppTypography.titleMedium),
          AppSpacing.vGapSm,
          Text(
            reason ??
                'Your application did not meet the current eligibility criteria.',
            style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
          ),
          AppSpacing.vGapLg,
          Row(
            children: [
              Expanded(
                child: VSButton(
                  label: 'Reapply',
                  onPressed: () =>
                      context.goNamed(RouteNames.identityVerification),
                ),
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: VSOutlinedButton(
                  label: 'Contact Support',
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
