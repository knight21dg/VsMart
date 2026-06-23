import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
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
      if (mounted) context.showSnack('Could not capture image', isError: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  UploadState _uploadState(String? path) {
    if (_uploading) return UploadState.uploading;
    return path != null ? UploadState.uploaded : UploadState.empty;
  }

  void _continue() {
    context.hideKeyboard();
    if (!_formKey.currentState!.validate()) return;
    final draft = ref.read(verificationControllerProvider);
    if (draft.panPath == null) {
      context.showSnack('Please upload your PAN card photo', isError: true);
      return;
    }
    context.pushNamed(RouteNames.selfieVerification);
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final draft = ref.watch(verificationControllerProvider);

    return Scaffold(
      appBar: const VSAppBar(title: 'PAN Verification'),
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
                    label: 'PAN Number',
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
                    'Your PAN is required for financial compliance.',
                    style: AppTypography.bodySmall
                        .copyWith(color: vs.textSecondary),
                  ),
                  AppSpacing.vGapLg,
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('Upload PAN Photo',
                          style: AppTypography.titleMedium),
                      AppSpacing.hGapSm,
                      Text('(Optional)',
                          style: AppTypography.bodySmall
                              .copyWith(color: vs.textSecondary)),
                    ],
                  ),
                  AppSpacing.vGapMd,
                  VSUploadCard(
                    title: 'PAN Card',
                    state: _uploadState(draft.panPath),
                    filePath: draft.panPath,
                    onCapture: () => _pick(ImageSource.camera),
                    onPickGallery: () => _pick(ImageSource.gallery),
                  ),
                  AppSpacing.vGapXl,
                  Text('Why we need this',
                      style: AppTypography.headlineMedium),
                  AppSpacing.vGapMd,
                  const _ReasonCard(
                    icon: Icons.credit_card_rounded,
                    tone: _ReasonTone.brand,
                    title: 'Credit Assessment',
                    body:
                        'To accurately evaluate your credit limit and offer '
                        'personalized financing.',
                  ),
                  AppSpacing.vGapMd,
                  const _ReasonCard(
                    icon: Icons.verified_user_rounded,
                    tone: _ReasonTone.success,
                    title: 'Identity Verification',
                    body:
                        'Ensuring your account belongs to you, preventing '
                        'fraud.',
                  ),
                  AppSpacing.vGapMd,
                  const _ReasonCard(
                    icon: Icons.shield_rounded,
                    tone: _ReasonTone.offer,
                    title: 'Risk Evaluation',
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_rounded, size: 16, color: vs.brand),
                      AppSpacing.hGapSm,
                      Text('100% Secure & Encrypted',
                          style: AppTypography.labelMedium
                              .copyWith(color: vs.brand)),
                    ],
                  ),
                  AppSpacing.vGapMd,
                  VSButton(
                    label: 'Verify PAN',
                    trailingIcon: Icons.arrow_forward_rounded,
                    onPressed: _continue,
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
                Text('Verification Pending',
                    style: AppTypography.titleMedium),
                Text('Please submit your details.',
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
