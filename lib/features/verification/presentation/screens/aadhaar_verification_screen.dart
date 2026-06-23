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

/// Step 1 of verification: the Aadhaar-only step. Captures the 12-digit Aadhaar
/// number and the front/back document images, autosaving every change to the
/// verification draft (preserving any PAN number already entered).
class AadhaarVerificationScreen extends ConsumerStatefulWidget {
  const AadhaarVerificationScreen({super.key});

  @override
  ConsumerState<AadhaarVerificationScreen> createState() =>
      _AadhaarVerificationScreenState();
}

enum _Doc { aadhaarFront, aadhaarBack }

class _AadhaarVerificationScreenState
    extends ConsumerState<AadhaarVerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _aadhaar = TextEditingController();
  final _picker = ImagePicker();
  final _uploading = <_Doc>{};

  @override
  void initState() {
    super.initState();
    _aadhaar.text = ref.read(verificationControllerProvider).aadhaarNumber;
  }

  @override
  void dispose() {
    _aadhaar.dispose();
    super.dispose();
  }

  /// Autosave the Aadhaar number while preserving any PAN number already in the
  /// draft (the PAN step writes it separately).
  void _saveNumber() {
    final draft = ref.read(verificationControllerProvider);
    ref.read(verificationControllerProvider.notifier).setIdentityNumbers(
          aadhaar: _aadhaar.text.trim(),
          pan: draft.panNumber,
        );
  }

  Future<void> _pick(_Doc doc, ImageSource source) async {
    setState(() => _uploading.add(doc));
    try {
      final file = await _picker.pickImage(source: source, imageQuality: 70);
      if (file == null) return;
      final path = await ref
          .read(imageCompressionServiceProvider)
          .compress(file.path);
      final ctrl = ref.read(verificationControllerProvider.notifier);
      switch (doc) {
        case _Doc.aadhaarFront:
          ctrl.setAadhaarFront(path);
          ref.read(analyticsServiceProvider).aadhaarUploaded();
        case _Doc.aadhaarBack:
          ctrl.setAadhaarBack(path);
      }
    } catch (_) {
      if (mounted) context.showSnack('Could not capture image', isError: true);
    } finally {
      if (mounted) setState(() => _uploading.remove(doc));
    }
  }

  UploadState _stateFor(_Doc doc, String? path) {
    if (_uploading.contains(doc)) return UploadState.uploading;
    return path != null ? UploadState.uploaded : UploadState.empty;
  }

  void _continue() {
    context.hideKeyboard();
    if (!_formKey.currentState!.validate()) return;
    final draft = ref.read(verificationControllerProvider);
    if (draft.aadhaarFrontPath == null || draft.aadhaarBackPath == null) {
      context.showSnack('Please upload Aadhaar front and back', isError: true);
      return;
    }
    context.pushNamed(RouteNames.panVerification);
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final draft = ref.watch(verificationControllerProvider);

    return Scaffold(
      appBar: const VSAppBar(title: 'Aadhaar Verification'),
      body: Column(
        children: [
          const VSVerificationProgress(step: 1, total: 4),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: AppSpacing.screen,
                children: [
                  Text('Verify Aadhaar', style: AppTypography.headlineMedium),
                  AppSpacing.vGapXs,
                  Text('Required to activate VS Credit.',
                      style: AppTypography.bodyMedium
                          .copyWith(color: vs.textSecondary)),
                  AppSpacing.vGapLg,
                  VSTextField(
                    controller: _aadhaar,
                    label: '12-Digit Aadhaar Number',
                    hint: '1234 5678 9012',
                    prefixIcon: Icons.badge_outlined,
                    keyboardType: TextInputType.number,
                    maxLength: 12,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: Validators.aadhaar,
                    onChanged: (_) => _saveNumber(),
                  ),
                  AppSpacing.vGapLg,
                  Text('Upload Aadhaar', style: AppTypography.titleLarge),
                  AppSpacing.vGapMd,
                  VSUploadCard(
                    title: 'Aadhaar Front',
                    state: _stateFor(_Doc.aadhaarFront, draft.aadhaarFrontPath),
                    filePath: draft.aadhaarFrontPath,
                    onCapture: () =>
                        _pick(_Doc.aadhaarFront, ImageSource.camera),
                    onPickGallery: () =>
                        _pick(_Doc.aadhaarFront, ImageSource.gallery),
                  ),
                  AppSpacing.vGapMd,
                  VSUploadCard(
                    title: 'Aadhaar Back',
                    state: _stateFor(_Doc.aadhaarBack, draft.aadhaarBackPath),
                    filePath: draft.aadhaarBackPath,
                    onCapture: () => _pick(_Doc.aadhaarBack, ImageSource.camera),
                    onPickGallery: () =>
                        _pick(_Doc.aadhaarBack, ImageSource.gallery),
                  ),
                  AppSpacing.vGapLg,
                  const _InfoCard(),
                  AppSpacing.vGapLg,
                  const _TrustRow(),
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
                  VSButton(
                    label: 'Continue',
                    trailingIcon: Icons.arrow_forward_rounded,
                    onPressed: _continue,
                  ),
                  AppSpacing.vGapSm,
                  Text(
                    'By continuing, you agree to our Terms of Service & '
                    'Privacy Policy.',
                    textAlign: TextAlign.center,
                    style: AppTypography.labelSmall
                        .copyWith(color: vs.textSecondary),
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

class _InfoCard extends StatelessWidget {
  const _InfoCard();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: vs.trustTint,
        borderRadius: AppRadius.brMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: vs.trust),
              AppSpacing.hGapSm,
              Text('We use Aadhaar verification to:',
                  style: AppTypography.labelLarge),
            ],
          ),
          AppSpacing.vGapSm,
          for (final t in const [
            'Verify identity',
            'Prevent fraud',
            'Determine credit eligibility',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('•  $t',
                  style: AppTypography.bodySmall
                      .copyWith(color: vs.textSecondary)),
            ),
        ],
      ),
    );
  }
}

class _TrustRow extends StatelessWidget {
  const _TrustRow();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    Widget item(IconData icon, String label) => Expanded(
          child: Column(
            children: [
              Icon(icon, size: 20, color: vs.brand),
              const SizedBox(height: AppSpacing.xs),
              Text(label,
                  textAlign: TextAlign.center,
                  style: AppTypography.labelSmall
                      .copyWith(color: vs.textSecondary)),
            ],
          ),
        );
    return Row(
      children: [
        item(Icons.lock_rounded, '256-bit\nEncryption'),
        item(Icons.verified_user_rounded, 'Government\nVerification'),
        item(Icons.storage_rounded, 'Secure\nStorage'),
      ],
    );
  }
}
