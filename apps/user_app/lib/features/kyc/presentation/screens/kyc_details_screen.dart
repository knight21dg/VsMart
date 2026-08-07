import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/l10n/status_labels.dart';
import '../../../../core/widgets/widgets.dart';
import '../../data/kyc_status_data.dart';

/// Read-only summary of the customer's submitted KYC documents and their
/// verification statuses, driven by the live `GET /kyc/status` response.
class KycDetailsScreen extends ConsumerWidget {
  const KycDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(kycStatusProvider);
    return Scaffold(
      appBar: VSAppBar(title: context.l10n.kycDetailsTitle),
      body: SafeArea(
        child: async.when(
          loading: () => const VSLoadingView(),
          error: (e, _) => VSErrorView(
            failure: e is Failure ? e : null,
            onRetry: () => ref.invalidate(kycStatusProvider),
          ),
          data: (info) => ListView(
            padding: AppSpacing.screen,
            children: [
              const _SecurityBanner(),
              AppSpacing.vGapLg,
              _StatusCard(info: info),
              if (info.isRejected && (info.rejectionReason ?? '').isNotEmpty) ...[
                AppSpacing.vGapMd,
                _RejectionCard(reason: info.rejectionReason!),
              ],
              AppSpacing.vGapXl,
              if (info.isNotStarted)
                _StartKycCard(onStart: () => context.pushNamed(RouteNames.kyc))
              else ...[
                Text(context.l10n.kycSubmittedDocs,
                    style: AppTypography.headlineMedium),
                AppSpacing.vGapLg,
                if (info.documents.isEmpty)
                  Text(context.l10n.kycNoDocuments,
                      style: AppTypography.bodyMedium
                          .copyWith(color: context.vsColors.textSecondary))
                else
                  for (final doc in info.documents) ...[
                    _DocumentCard(doc: doc),
                    AppSpacing.vGapMd,
                  ],
              ],
              AppSpacing.vGapXs,
              const _HelpCard(),
            ],
          ),
        ),
      ),
    );
  }
}

VSStatusTone _toneForStatus(String status) => switch (status) {
      'verified' || 'approved' || 'completed' => VSStatusTone.success,
      'rejected' => VSStatusTone.danger,
      _ => VSStatusTone.warning,
    };

class _SecurityBanner extends StatelessWidget {
  const _SecurityBanner();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(color: vs.trustTint, borderRadius: AppRadius.brLg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined, color: vs.trust, size: 22),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.kycDataSecured,
                    style: AppTypography.titleMedium),
                AppSpacing.vGapXs,
                Text(
                  context.l10n.kycSecurityBannerBody,
                  style:
                      AppTypography.bodySmall.copyWith(color: vs.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.info});

  final KycStatusInfo info;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final pct = (info.progress * 100).round();
    final caption = info.isVerified
        ? context.l10n.kycCaptionVerified
        : info.isPending
            ? context.l10n.kycCaptionPending
            : info.isRejected
                ? context.l10n.kycCaptionRejected
                : context.l10n.kycCaptionNotStarted;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
        boxShadow: AppShadows.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(context.l10n.kycVerificationStatus,
                    style: AppTypography.displayMedium),
              ),
              AppSpacing.hGapMd,
              VSStatusChip(
                label: context.l10n.kycPercentComplete(pct),
                tone: _toneForStatus(info.status),
                icon: info.isVerified
                    ? Icons.verified_rounded
                    : Icons.hourglass_bottom_rounded,
              ),
            ],
          ),
          AppSpacing.vGapMd,
          Text(caption,
              style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary)),
          AppSpacing.vGapLg,
          ClipRRect(
            borderRadius: AppRadius.brPill,
            child: LinearProgressIndicator(
              value: info.progress,
              minHeight: 6,
              backgroundColor: vs.border,
              valueColor: AlwaysStoppedAnimation(vs.brand),
            ),
          ),
        ],
      ),
    );
  }
}

class _RejectionCard extends StatelessWidget {
  const _RejectionCard({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: vs.dangerTint,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 20, color: vs.danger),
          AppSpacing.hGapSm,
          Expanded(
            child: Text(context.l10n.kycReason(reason),
                style: AppTypography.bodySmall.copyWith(color: vs.danger)),
          ),
        ],
      ),
    );
  }
}

class _StartKycCard extends StatelessWidget {
  const _StartKycCard({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
      ),
      child: Column(
        children: [
          Icon(Icons.assignment_ind_outlined, size: 40, color: vs.brand),
          AppSpacing.vGapMd,
          Text(context.l10n.kycCompleteTitle,
              style: AppTypography.titleMedium),
          AppSpacing.vGapXs,
          Text(
            context.l10n.kycStartCardBody,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(color: vs.textSecondary),
          ),
          AppSpacing.vGapLg,
          VSButton(label: context.l10n.kycStartCta, onPressed: onStart),
        ],
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.doc});

  final KycDocumentInfo doc;

  IconData get _icon => switch (doc.type) {
        'aadhaar' => Icons.badge_outlined,
        'pan' => Icons.credit_card_rounded,
        'selfie' => Icons.videocam_outlined,
        'residence' => Icons.location_on_outlined,
        _ => Icons.description_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final value = doc.numberMasked.isNotEmpty
        ? doc.numberMasked
        : context.l10n.kycSubmitted;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: vs.trustTint,
              borderRadius: AppRadius.brPill,
            ),
            child: Icon(_icon, color: vs.trust, size: 22),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kycDocLabel(context.l10n, doc.type),
                    style: AppTypography.titleMedium),
                AppSpacing.vGapXs,
                Text(value,
                    style: AppTypography.bodyMedium
                        .copyWith(color: vs.textSecondary)),
              ],
            ),
          ),
          AppSpacing.hGapSm,
          VSStatusChip(
            label: kycStatusLabel(context.l10n, doc.status),
            tone: _toneForStatus(doc.status),
            dense: true,
          ),
        ],
      ),
    );
  }
}

class _HelpCard extends StatelessWidget {
  const _HelpCard();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Material(
      color: context.colors.surface,
      borderRadius: AppRadius.brLg,
      child: InkWell(
        onTap: () => context.pushNamed(RouteNames.support),
        borderRadius: AppRadius.brLg,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: AppRadius.brLg,
            border: Border.all(color: vs.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.help_outline_rounded,
                  size: 20, color: context.textStyles.bodyLarge?.color),
              AppSpacing.hGapMd,
              Text(context.l10n.kycNeedHelp, style: AppTypography.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}
