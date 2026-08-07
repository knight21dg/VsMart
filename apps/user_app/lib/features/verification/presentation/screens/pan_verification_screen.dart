import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/app_error_presenter.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../auth/presentation/providers/session_provider.dart';
import '../providers/verification_providers.dart';
import '../widgets/verification_widgets.dart';

/// Dedicated PAN verification step (step 2 of 4): captures the PAN number and an
/// optional PAN card photo. The number autosaves to the verification draft while
/// preserving the previously entered Aadhaar value.
class PanVerificationScreen extends ConsumerStatefulWidget {
  const PanVerificationScreen({super.key});

  @override
  ConsumerState<PanVerificationScreen> createState() =>
      _PanVerificationScreenState();
}

class _PanVerificationScreenState extends ConsumerState<PanVerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pan = TextEditingController();
  final _picker = ImagePicker();
  bool _uploading = false;
  bool _verifying = false;
  bool _consent = false;

  @override
  void initState() {
    super.initState();
    _pan.text = ref.read(verificationControllerProvider).panNumber;
  }

  @override
  void dispose() {
    _pan.dispose();
    super.dispose();
  }

  void _saveNumber() {
    final draft = ref.read(verificationControllerProvider);
    ref.read(verificationControllerProvider.notifier).setIdentityNumbers(
          aadhaar: draft.aadhaarNumber,
          pan: _pan.text.trim(),
        );
  }

  Future<void> _pick(ImageSource source) async {
    setState(() => _uploading = true);
    try {
      final file = await _picker.pickImage(source: source, imageQuality: 70);
      if (file == null) return;
      final path =
          await ref.read(imageCompressionServiceProvider).compress(file.path);
      ref.read(verificationControllerProvider.notifier).setPan(path);
      ref.read(analyticsServiceProvider).panUploaded();
    } catch (_) {
      if (mounted) {
        context.showSnack(context.l10n.verificationCouldNotCaptureImage,
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  UploadState _uploadState(String? path) {
    if (_uploading) return UploadState.uploading;
    return path != null ? UploadState.uploaded : UploadState.empty;
  }

  /// Verify the PAN against the government source, then advance. A failed check
  /// (invalid PAN, name mismatch, duplicate) returns a coded [Failure] which the
  /// central presenter turns into the right message/retry. A PAN card photo is
  /// mandatory — document uploads are always required to submit the application.
  Future<void> _verifyAndContinue() async {
    context.hideKeyboard();
    if (!_formKey.currentState!.validate()) return;
    if (!_consent) {
      context.showSnack(context.l10n.verificationPanConsentRequired,
          isError: true);
      return;
    }
    if (ref.read(verificationControllerProvider).panPath == null) {
      context.showSnack('Please upload your PAN card photo', isError: true);
      return;
    }
    _saveNumber();
    final name = ref.read(sessionControllerProvider).user?.name ?? '';
    setState(() => _verifying = true);
    final result = await ref.read(verificationRepositoryProvider).verifyPan(
          pan: _pan.text.trim().toUpperCase(),
          name: name,
          consent: true,
        );
    if (!mounted) return;
    setState(() => _verifying = false);
    result.fold(
      (failure) => presentFailure(context, ref, failure),
      (_) {
        context.showSnack(context.l10n.verificationPanVerified);
        context.pushNamed(RouteNames.selfieVerification);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final draft = ref.watch(verificationControllerProvider);

    return Scaffold(
      appBar: VSAppBar(title: context.l10n.verifyPan),
      body: Column(
        children: [
          const VSVerificationProgress(step: 2, total: 4),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: AppSpacing.screen,
                children: [
                  const _StatusBanner(),
                  AppSpacing.vGapLg,
                  VSTextField(
                    controller: _pan,
                    label: context.l10n.verifyPanNumber,
                    hint: 'ABCDE1234F',
                    prefixIcon: Icons.badge_outlined,
                    maxLength: 10,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      TextInputFormatter.withFunction(
                        (oldV, newV) =>
                            newV.copyWith(text: newV.text.toUpperCase()),
                      ),
                    ],
                    validator: Validators.pan,
                    onChanged: (_) => _saveNumber(),
                  ),
                  AppSpacing.vGapSm,
                  Text(
                    context.l10n.verificationPanComplianceNote,
                    style: AppTypography.bodySmall
                        .copyWith(color: vs.textSecondary),
                  ),
                  AppSpacing.vGapLg,
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(context.l10n.verifyUploadPan,
                          style: AppTypography.titleMedium),
                      AppSpacing.hGapSm,
                      Text('(required)',
                          style: AppTypography.bodySmall
                              .copyWith(color: vs.danger)),
                    ],
                  ),
                  AppSpacing.vGapMd,
                  VSUploadCard(
                    title: context.l10n.kycDocPan,
                    state: _uploadState(draft.panPath),
                    filePath: draft.panPath,
                    onCapture: () => _pick(ImageSource.camera),
                    onPickGallery: () => _pick(ImageSource.gallery),
                  ),
                  AppSpacing.vGapXl,
                  Text(context.l10n.verifyWhyNeed,
                      style: AppTypography.headlineMedium),
                  AppSpacing.vGapMd,
                  _ReasonCard(
                    icon: Icons.credit_card_rounded,
                    tone: _ReasonTone.brand,
                    title: context.l10n.verifyCreditAssessment,
                    body:
                        'To accurately evaluate your credit limit and offer '
                        'personalized financing.',
                  ),
                  AppSpacing.vGapMd,
                  _ReasonCard(
                    icon: Icons.verified_user_rounded,
                    tone: _ReasonTone.success,
                    title: context.l10n.verifyIdentityVerification,
                    body:
                        'Ensuring your account belongs to you, preventing '
                        'fraud.',
                  ),
                  AppSpacing.vGapMd,
                  _ReasonCard(
                    icon: Icons.shield_rounded,
                    tone: _ReasonTone.offer,
                    title: context.l10n.verificationRiskEvaluation,
                    body:
                        'Maintaining a secure platform for all our users in '
                        'compliance with regulations.',
                  ),
                ],
              ),
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
                  InkWell(
                    onTap: () => setState(() => _consent = !_consent),
                    borderRadius: AppRadius.brSm,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: _consent,
                          onChanged: (v) =>
                              setState(() => _consent = v ?? false),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              context.l10n.verificationPanConsentText,
                              style: AppTypography.labelSmall
                                  .copyWith(color: vs.textSecondary),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  AppSpacing.vGapSm,
                  VSButton(
                    label: context.l10n.verificationVerifyPan,
                    trailingIcon: Icons.arrow_forward_rounded,
                    isLoading: _verifying,
                    onPressed: _verifyAndContinue,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pending-status banner shown at the top of the form.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner();

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
          Container(
            height: 36,
            width: 36,
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: AppRadius.brSm,
            ),
            child: Icon(Icons.hourglass_empty_rounded,
                size: 18, color: vs.trust),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.verifyPending,
                    style: AppTypography.titleMedium),
                Text(context.l10n.verificationSubmitYourDetails,
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

enum _ReasonTone { brand, success, offer }

/// A single "Why we need this" reason row with a tinted leading icon.
class _ReasonCard extends StatelessWidget {
  const _ReasonCard({
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final _ReasonTone tone;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final (fg, bg) = switch (tone) {
      _ReasonTone.brand => (vs.brand, vs.brandTint),
      _ReasonTone.success => (vs.success, vs.successTint),
      _ReasonTone.offer => (vs.offer, vs.offerTint),
    };
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 36,
            width: 36,
            decoration: BoxDecoration(color: bg, borderRadius: AppRadius.brSm),
            child: Icon(icon, size: 18, color: fg),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.titleMedium),
                AppSpacing.vGapXs,
                Text(body,
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
