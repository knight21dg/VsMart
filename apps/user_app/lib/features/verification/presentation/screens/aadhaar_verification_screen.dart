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
  final _otp = TextEditingController();
  final _picker = ImagePicker();
  final _uploading = <_Doc>{};
  bool _busy = false; // an OTP send/verify call is in flight
  bool _otpSent = false; // the OTP field is showing
  bool _otpVerified = false; // OTP confirmed — only the uploads may remain
  String? _otpRef; // reference id from send-otp

  @override
  void initState() {
    super.initState();
    _aadhaar.text = ref.read(verificationControllerProvider).aadhaarNumber;
  }

  @override
  void dispose() {
    _aadhaar.dispose();
    _otp.dispose();
    super.dispose();
  }

  /// Step 1 of the OTP path: send the OTP to the Aadhaar-linked mobile. No
  /// DigiLocker account needed — just the linked number.
  Future<void> _sendOtp() async {
    context.hideKeyboard();
    if (Validators.aadhaar(_aadhaar.text) != null) {
      context.showSnack(context.l10n.verificationAadhaarInvalid, isError: true);
      return;
    }
    _saveNumber();
    setState(() => _busy = true);
    final result = await ref
        .read(verificationRepositoryProvider)
        .sendAadhaarOtp(aadhaar: _aadhaar.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    result.fold(
      (failure) => presentFailure(context, ref, failure),
      (res) {
        setState(() {
          _otpSent = true;
          _otpRef = res.referenceId;
        });
        context.showSnack(context.l10n.verificationOtpSentAadhaar);
      },
    );
  }

  /// Step 2 of the OTP path: verify the OTP, then advance to the PAN step — but
  /// only once BOTH Aadhaar images are captured (document uploads are always
  /// required to submit). If the images are still missing, verification is
  /// recorded and the button turns into "Continue" so the user can upload first.
  Future<void> _verifyOtp() async {
    context.hideKeyboard();
    final otp = _otp.text.trim();
    if (otp.length < 4 || _otpRef == null) {
      context.showSnack(context.l10n.verificationEnterOtpReceived, isError: true);
      return;
    }
    setState(() => _busy = true);
    final result = await ref.read(verificationRepositoryProvider).verifyAadhaarOtp(
          referenceId: _otpRef!,
          otp: otp,
          aadhaar: _aadhaar.text.trim(),
        );
    if (!mounted) return;
    setState(() => _busy = false);
    result.fold(
      (failure) => presentFailure(context, ref, failure),
      (_) {
        context.showSnack(context.l10n.verificationAadhaarVerified);
        setState(() => _otpVerified = true);
        _goToPan();
      },
    );
  }

  /// Advance to the PAN step, enforcing that both Aadhaar images are present.
  /// Both the OTP path and the "can't receive OTP" path funnel through here so
  /// the front/back uploads are mandatory regardless of how identity was proven.
  void _goToPan() {
    final draft = ref.read(verificationControllerProvider);
    if (draft.aadhaarFrontPath == null || draft.aadhaarBackPath == null) {
      context.showSnack(context.l10n.verificationUploadAadhaarBoth,
          isError: true);
      return;
    }
    context.pushNamed(RouteNames.panVerification);
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
      if (mounted) {
        context.showSnack(context.l10n.verificationCouldNotCaptureImage,
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _uploading.remove(doc));
    }
  }

  UploadState _stateFor(_Doc doc, String? path) {
    if (_uploading.contains(doc)) return UploadState.uploading;
    return path != null ? UploadState.uploaded : UploadState.empty;
  }

  /// Fallback path for users who can't receive the Aadhaar OTP (e.g. Aadhaar not
  /// linked to their current mobile): proceed with uploaded document photos, which
  /// an agent reviews manually. Requires both sides to be captured.
  void _continueWithDocuments() {
    context.hideKeyboard();
    if (Validators.aadhaar(_aadhaar.text) != null) {
      context.showSnack(context.l10n.verificationAadhaarInvalid, isError: true);
      return;
    }
    _saveNumber();
    _goToPan();
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final draft = ref.watch(verificationControllerProvider);

    return Scaffold(
      appBar: VSAppBar(title: context.l10n.verifyAadhaar),
      body: Column(
        children: [
          const VSVerificationProgress(step: 1, total: 4),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: AppSpacing.screen,
                children: [
                  Text(context.l10n.verifyAadhaar,
                      style: AppTypography.headlineMedium),
                  AppSpacing.vGapXs,
                  Text(context.l10n.verificationRequiredForCredit,
                      style: AppTypography.bodyMedium
                          .copyWith(color: vs.textSecondary)),
                  AppSpacing.vGapLg,
                  VSTextField(
                    controller: _aadhaar,
                    label: context.l10n.verifyAadhaarNumber,
                    hint: '1234 5678 9012',
                    prefixIcon: Icons.badge_outlined,
                    keyboardType: TextInputType.number,
                    maxLength: 12,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: Validators.aadhaar,
                    onChanged: (_) => _saveNumber(),
                  ),
                  if (_otpSent) ...[
                    AppSpacing.vGapMd,
                    VSTextField(
                      controller: _otp,
                      label: context.l10n.authEnterOtp,
                      hint: '6-digit OTP',
                      prefixIcon: Icons.sms_outlined,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _busy ? null : _sendOtp,
                        child: Text(context.l10n.authResendOtp),
                      ),
                    ),
                  ],
                  AppSpacing.vGapLg,
                  Text(context.l10n.verifyUploadAadhaar,
                      style: AppTypography.titleLarge),
                  AppSpacing.vGapXs,
                  Text(context.l10n.verificationOtpOptionalNote,
                      style: AppTypography.bodySmall
                          .copyWith(color: vs.textSecondary)),
                  AppSpacing.vGapMd,
                  VSUploadCard(
                    title: context.l10n.verificationAadhaarFront,
                    state: _stateFor(_Doc.aadhaarFront, draft.aadhaarFrontPath),
                    filePath: draft.aadhaarFrontPath,
                    onCapture: () =>
                        _pick(_Doc.aadhaarFront, ImageSource.camera),
                    onPickGallery: () =>
                        _pick(_Doc.aadhaarFront, ImageSource.gallery),
                  ),
                  AppSpacing.vGapMd,
                  VSUploadCard(
                    title: context.l10n.verificationAadhaarBack,
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
                    label: _otpVerified
                        ? 'Continue'
                        : (_otpSent ? 'Verify & Continue' : 'Send OTP'),
                    trailingIcon: _otpVerified || _otpSent
                        ? Icons.arrow_forward_rounded
                        : Icons.sms_rounded,
                    isLoading: _busy,
                    onPressed: _otpVerified
                        ? _goToPan
                        : (_otpSent ? _verifyOtp : _sendOtp),
                  ),
                  AppSpacing.vGapXs,
                  TextButton(
                    onPressed: _busy ? null : _continueWithDocuments,
                    child: Text(
                      context.l10n.verificationCantReceiveOtp,
                      style: AppTypography.labelMedium
                          .copyWith(color: vs.textSecondary),
                    ),
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
              Text(context.l10n.verificationWhyAadhaarTitle,
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
