import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/extensions/context_extensions.dart';
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
      appBar: const VSAppBar(title: 'KYC Details'),
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
                Text('Submitted Documents',
                    style: AppTypography.headlineMedium),
                AppSpacing.vGapLg,
                if (info.documents.isEmpty)
                  Text('No documents on file yet.',
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

String _statusLabel(String status) => switch (status) {
      'verified' || 'approved' => 'Verified',
      'rejected' => 'Rejected',
      'pending' => 'Under Review',
      _ => status.isEmpty ? 'Pending' : status[0].toUpperCase() + status.substring(1),
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
                Text('Your data is secured', style: AppTypography.titleMedium),
                AppSpacing.vGapXs,
                Text(
                  'KYC verification is required to unlock your full credit '
                  'limit and ensure compliance with RBI regulations. We use '
                  'bank-grade encryption.',
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
        ? 'All required documents have been successfully verified.'
        : info.isPending
            ? 'Your documents are under review. This usually takes 1–2 days.'
            : info.isRejected
                ? 'Some documents could not be verified. Please re-submit.'
                : 'Complete your KYC to unlock your full credit limit.';
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
                child: Text('Verification\nStatus',
                    style: AppTypography.displayMedium),
              ),
              AppSpacing.hGapMd,
              VSStatusChip(
                label: '$pct% Complete',
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
            child: Text('Reason: $reason',
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
          Text('Complete your KYC', style: AppTypography.titleMedium),
          AppSpacing.vGapXs,
          Text(
            'Submit your Aadhaar, PAN and a selfie to verify your identity.',
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(color: vs.textSecondary),
          ),
          AppSpacing.vGapLg,
          VSButton(label: 'Start KYC', onPressed: onStart),
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
    final value = doc.numberMasked.isNotEmpty ? doc.numberMasked : 'Submitted';
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
                Text(doc.label, style: AppTypography.titleMedium),
                AppSpacing.vGapXs,
                Text(value,
                    style: AppTypography.bodyMedium
                        .copyWith(color: vs.textSecondary)),
              ],
            ),
          ),
          AppSpacing.hGapSm,
          VSStatusChip(
            label: _statusLabel(doc.status),
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
              Text('Need Help with KYC?', style: AppTypography.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}
