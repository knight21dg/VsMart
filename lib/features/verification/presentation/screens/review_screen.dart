import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../address/presentation/providers/address_providers.dart';
import '../../../auth/presentation/providers/current_user_provider.dart';
import '../../domain/entities/verification_draft.dart';
import '../../domain/entities/verification_enums.dart';
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
      context.showSnack('Submission failed. Please try again.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final draft = ref.watch(verificationControllerProvider);
    final user = ref.watch(currentUserProvider);
    final address = ref.watch(defaultAddressProvider);

    return Scaffold(
      appBar: const VSAppBar(title: 'Review Application'),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: AppSpacing.screen,
              children: [
                Text('Review Your Application',
                    style: AppTypography.headlineSmall),
                AppSpacing.vGapXs,
                Text('Check each section before submitting for approval.',
                    style: AppTypography.bodyMedium
                        .copyWith(color: vs.textSecondary)),
                AppSpacing.vGapLg,
                VSReviewSection(
                  title: 'Personal Details',
                  icon: Icons.person_outline_rounded,
                  complete: (user?.name.isNotEmpty ?? false),
                  onEdit: () => context.pushNamed(RouteNames.register),
                  children: [
                    VSReviewRow(label: 'Name', value: user?.name ?? ''),
                    VSReviewRow(label: 'Phone', value: user?.phone ?? ''),
                    VSReviewRow(label: 'Email', value: user?.email ?? ''),
                  ],
                ),
                AppSpacing.vGapMd,
                VSReviewSection(
                  title: 'Address Details',
                  icon: Icons.location_on_outlined,
                  complete: address != null,
                  onEdit: () => context.pushNamed(RouteNames.addresses),
                  children: [
                    VSReviewRow(label: 'Name', value: address?.name ?? ''),
                    VSReviewRow(label: 'Phone', value: address?.phone ?? ''),
                    VSReviewRow(
                        label: 'Address', value: address?.formatted ?? ''),
                  ],
                ),
                AppSpacing.vGapMd,
                VSReviewSection(
                  title: 'Identity Documents',
                  icon: Icons.badge_outlined,
                  complete: draft.isIdentityComplete,
                  onEdit: () =>
                      context.pushNamed(RouteNames.identityVerification),
                  children: [
                    VSReviewRow(
                        label: 'Aadhaar', value: _maskAadhaar(draft.aadhaarNumber)),
                    VSReviewRow(label: 'PAN', value: draft.panNumber),
                    VSReviewRow(
                        label: 'Documents', value: _docsSummary(draft)),
                  ],
                ),
                AppSpacing.vGapMd,
                VSReviewSection(
                  title: 'Selfie Verification',
                  icon: Icons.face_outlined,
                  complete: draft.isSelfieComplete,
                  onEdit: () => context.pushNamed(RouteNames.selfieVerification),
                  children: [
                    VSReviewRow(
                      label: 'Selfie',
                      value: draft.isSelfieComplete ? 'Captured' : 'Pending',
                    ),
                  ],
                ),
                AppSpacing.vGapMd,
                VSReviewSection(
                  title: 'Credit Information',
                  icon: Icons.account_balance_wallet_outlined,
                  complete: draft.isCreditComplete,
                  onEdit: () => context.pushNamed(RouteNames.creditApplication),
                  children: [
                    VSReviewRow(label: 'Occupation', value: draft.occupation),
                    VSReviewRow(
                        label: 'Monthly Income',
                        value: draft.monthlyIncome?.asCurrency ?? ''),
                    VSReviewRow(
                        label: 'Family Members',
                        value: draft.familyMembers?.toString() ?? ''),
                    VSReviewRow(
                        label: 'House', value: _houseLabel(draft.houseType)),
                    VSReviewRow(
                        label: 'Ownership',
                        value: _ownershipLabel(draft.ownership)),
                    VSReviewRow(
                        label: 'Requested Limit',
                        value: draft.requestedLimit?.asCurrency ?? ''),
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
                        'Complete all sections to submit your application.',
                        style: AppTypography.bodySmall
                            .copyWith(color: vs.warning),
                      ),
                    ),
                  VSButton(
                    label: 'Submit Application',
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

  String _houseLabel(HouseType? t) => switch (t) {
        HouseType.independent => 'Independent',
        HouseType.apartment => 'Apartment',
        HouseType.shared => 'Shared',
        null => '',
      };

  String _ownershipLabel(Ownership? o) => switch (o) {
        Ownership.owned => 'Owned',
        Ownership.rented => 'Rented',
        Ownership.family => 'Family',
        null => '',
      };
}
