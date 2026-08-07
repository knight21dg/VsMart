import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../address/presentation/providers/address_providers.dart';
import '../../../auth/presentation/providers/current_user_provider.dart';
import '../../domain/entities/verification_draft.dart';
import '../providers/verification_providers.dart';
import '../widgets/review_widgets.dart';

/// Step 4 of verification: review every section before submitting. Submit is
/// enabled only when [VerificationDraft.isReadyToSubmit] is true.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  bool _submitting = false;

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final application =
        await ref.read(verificationControllerProvider.notifier).submit();
    if (!mounted) return;
    setState(() => _submitting = false);
    if (application != null) {
      ref.read(analyticsServiceProvider).applicationSubmitted();
      context.pushReplacementNamed(RouteNames.applicationSubmitted);
    } else {
      context.showSnack(context.l10n.verificationSubmissionFailed,
          isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final draft = ref.watch(verificationControllerProvider);
    final user = ref.watch(currentUserProvider);
    final address = ref.watch(defaultAddressProvider);

    return Scaffold(
      appBar: VSAppBar(title: context.l10n.verifyReviewApp),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: AppSpacing.screen,
              children: [
                Text(context.l10n.verifyReviewApp,
                    style: AppTypography.headlineSmall),
                AppSpacing.vGapXs,
                Text(context.l10n.verifyReviewBeforeSubmit,
                    style: AppTypography.bodyMedium
                        .copyWith(color: vs.textSecondary)),
                AppSpacing.vGapLg,
                VSReviewSection(
                  title: context.l10n.verifyPersonalDetails,
                  icon: Icons.person_outline_rounded,
                  complete: (user?.name.isNotEmpty ?? false),
                  onEdit: () => context.pushNamed(RouteNames.register),
                  children: [
                    VSReviewRow(
                        label: context.l10n.accountName,
                        value: user?.name ?? ''),
                    VSReviewRow(
                        label: context.l10n.accountPhone,
                        value: user?.phone ?? ''),
                    VSReviewRow(
                        label: context.l10n.accountEmail,
                        value: user?.email ?? ''),
                  ],
                ),
                AppSpacing.vGapMd,
                VSReviewSection(
                  title: context.l10n.verifyAddressDetails,
                  icon: Icons.location_on_outlined,
                  complete: address != null,
                  onEdit: () => context.pushNamed(RouteNames.addresses),
                  children: [
                    VSReviewRow(
                        label: context.l10n.accountName,
                        value: address?.name ?? ''),
                    VSReviewRow(
                        label: context.l10n.accountPhone,
                        value: address?.phone ?? ''),
                    VSReviewRow(
                        label: context.l10n.verificationAddress,
                        value: address?.formatted ?? ''),
                  ],
                ),
                AppSpacing.vGapMd,
                VSReviewSection(
                  title: context.l10n.verifyIdentityDocs,
                  icon: Icons.badge_outlined,
                  complete: draft.isIdentityComplete,
                  onEdit: () =>
                      context.pushNamed(RouteNames.identityVerification),
                  children: [
                    VSReviewRow(
                        label: 'Aadhaar', value: _maskAadhaar(draft.aadhaarNumber)),
                    VSReviewRow(label: 'PAN', value: draft.panNumber),
                    VSReviewRow(
                        label: context.l10n.verifyDocuments,
                        value: _docsSummary(draft)),
                  ],
                ),
                AppSpacing.vGapMd,
                VSReviewSection(
                  title: context.l10n.verifySelfie,
                  icon: Icons.face_outlined,
                  complete: draft.isSelfieComplete,
                  onEdit: () => context.pushNamed(RouteNames.selfieVerification),
                  children: [
                    VSReviewRow(
                      label: context.l10n.verificationSelfie,
                      value: draft.isSelfieComplete
                          ? 'Captured'
                          : context.l10n.verifyStatusPending,
                    ),
                  ],
                ),
                AppSpacing.vGapMd,
                VSReviewSection(
                  title: context.l10n.verifyResidence,
                  icon: Icons.home_outlined,
                  complete: draft.isResidenceComplete,
                  onEdit: () =>
                      context.pushNamed(RouteNames.residenceVerification),
                  children: [
                    VSReviewRow(
                      label: context.l10n.verifyResidence,
                      value: draft.residencePhotoPath != null
                          ? 'Captured'
                          : context.l10n.verifyStatusPending,
                    ),
                    VSReviewRow(
                      label: context.l10n.verifyLocation,
                      value: draft.isResidenceComplete
                          ? '${draft.residenceLatitude!.toStringAsFixed(5)}, '
                              '${draft.residenceLongitude!.toStringAsFixed(5)}'
                          : context.l10n.verifyStatusPending,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: context.colors.surface,
              border: Border(top: BorderSide(color: vs.border)),
            ),
            child: SafeArea(
              minimum: AppSpacing.screen,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!draft.isReadyToSubmit)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(
                        context.l10n.verificationCompleteAllSections,
                        style: AppTypography.bodySmall
                            .copyWith(color: vs.warning),
                      ),
                    ),
                  VSButton(
                    label: context.l10n.verifySubmitApp,
                    isLoading: _submitting,
                    onPressed: draft.isReadyToSubmit ? _submit : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _maskAadhaar(String aadhaar) {
    if (aadhaar.length < 4) return aadhaar;
    return 'XXXX XXXX ${aadhaar.substring(aadhaar.length - 4)}';
  }

  String _docsSummary(VerificationDraft d) {
    final n = [d.aadhaarFrontPath, d.aadhaarBackPath, d.panPath]
        .where((p) => p != null)
        .length;
    return '$n of 3 uploaded';
  }

}
