import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/app_error_presenter.dart';
import '../../../../core/errors/error_handler.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/image_pick_helper.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../auth/presentation/providers/current_user_provider.dart';
import '../../data/credit_kyc_data.dart';

/// Apply for VS Credit — a two-phase flow:
///   1. CHECK: enter name (as per PAN), DOB and PAN → we pull your CIBIL score
///      for your registered number and verify it matches (name + PAN + score).
///   2. DOCUMENTS: upload your Aadhaar + PAN scans → an agent is assigned to
///      verify your details.
class CreditKycScreen extends ConsumerStatefulWidget {
  const CreditKycScreen({super.key});

  @override
  ConsumerState<CreditKycScreen> createState() => _CreditKycScreenState();
}

enum _Step { details, documents, done }

class _CreditKycScreenState extends ConsumerState<CreditKycScreen> {
  final _name = TextEditingController();
  final _pan = TextEditingController();
  DateTime? _dob;
  bool _consent = false;

  String? _aadhaarFrontPath;
  String? _aadhaarBackPath;
  String? _panFrontPath;
  String? _panBackPath;

  _Step _step = _Step.details;
  CreditCheckResult? _check;
  bool _busy = false;

  static final _panRe = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');

  @override
  void initState() {
    super.initState();
    _name.text = ref.read(currentUserProvider)?.name ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _pan.dispose();
    super.dispose();
  }

  void _fail(Object e) => presentFailure(context, ref, ErrorHandler.handle(e));

  bool get _detailsValid =>
      _name.text.trim().length >= 3 &&
      _dob != null &&
      _panRe.hasMatch(_pan.text.trim().toUpperCase()) &&
      _consent;

  bool get _docsValid =>
      _aadhaarFrontPath != null &&
      _aadhaarBackPath != null &&
      _panFrontPath != null &&
      _panBackPath != null;

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 18, now.month, now.day),
      helpText: context.l10n.kycDobHelpText,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  Future<void> _pick(void Function(String) set) async {
    final file = await pickImageFromSource(context);
    if (file != null) setState(() => set(file.path));
  }

  Future<void> _runCheck() async {
    if (!_detailsValid) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final result = await ref.read(creditKycDataSourceProvider).checkCibil(
            fullName: _name.text.trim(),
            dob: DateFormat('yyyy-MM-dd').format(_dob!),
            pan: _pan.text.trim().toUpperCase(),
            consent: _consent,
          );
      if (mounted) {
        setState(() {
          _check = result;
          _step = _Step.documents;
        });
      }
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitDocs() async {
    if (!_docsValid) return;
    setState(() => _busy = true);
    try {
      await ref.read(creditKycDataSourceProvider).submitDocuments(
            consent: true,
            aadhaarFrontPath: _aadhaarFrontPath!,
            aadhaarBackPath: _aadhaarBackPath!,
            panFrontPath: _panFrontPath!,
            panBackPath: _panBackPath!,
          );
      if (mounted) setState(() => _step = _Step.done);
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.kycApplyVsCredit,
            style: AppTypography.headlineSmall.copyWith(color: vs.brand)),
      ),
      body: SafeArea(
        child: switch (_step) {
          _Step.details => _detailsView(vs),
          _Step.documents => _documentsView(vs),
          _Step.done => _doneView(vs),
        },
      ),
    );
  }

  // ── Phase 1: identity + CIBIL check ──
  Widget _detailsView(VSColors vs) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: AppSpacing.screen,
            children: [
              Text(context.l10n.kycStep1VerifyDetails,
                  style: AppTypography.labelMedium
                      .copyWith(color: vs.textSecondary)),
              AppSpacing.vGapSm,
              Text(context.l10n.kycDetailsIntro,
                  style:
                      AppTypography.bodyMedium.copyWith(color: vs.textSecondary)),
              AppSpacing.vGapLg,
              _SectionTitle(context.l10n.kycNameAsPerPan),
              AppSpacing.vGapSm,
              VSTextField(
                controller: _name,
                label: context.l10n.addressFullName,
                hint: context.l10n.kycFullNameHint,
                prefixIcon: Icons.person_outline_rounded,
                onChanged: (_) => setState(() {}),
              ),
              AppSpacing.vGapMd,
              _SectionTitle(context.l10n.profileDob),
              AppSpacing.vGapSm,
              InkWell(
                onTap: _pickDob,
                borderRadius: BorderRadius.circular(10),
                child: IgnorePointer(
                  child: VSTextField(
                    label: context.l10n.profileDob,
                    hint: context.l10n.kycSelectDob,
                    prefixIcon: Icons.calendar_today_rounded,
                    controller: TextEditingController(
                      text: _dob == null
                          ? ''
                          : DateFormat('d MMM yyyy').format(_dob!),
                    ),
                  ),
                ),
              ),
              AppSpacing.vGapMd,
              _SectionTitle(context.l10n.verifyPanNumber),
              AppSpacing.vGapSm,
              VSTextField(
                controller: _pan,
                label: context.l10n.verifyPanNumber,
                hint: 'ABCDE1234F',
                maxLength: 10,
                prefixIcon: Icons.badge_outlined,
                inputFormatters: [
                  UpperCaseTextFormatter(),
                  LengthLimitingTextInputFormatter(10),
                ],
                onChanged: (_) => setState(() {}),
              ),
              AppSpacing.vGapMd,
              _ConsentTile(
                value: _consent,
                onChanged: (v) => setState(() => _consent = v),
              ),
            ],
          ),
        ),
        _bottomBar(
          child: VSButton(
            label: context.l10n.kycCheckCibil,
            isLoading: _busy,
            onPressed: (_busy || !_detailsValid) ? null : _runCheck,
          ),
        ),
      ],
    );
  }

  // ── Phase 2: documents ──
  Widget _documentsView(VSColors vs) {
    final c = _check!;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: AppSpacing.screen,
            children: [
              // Verified score banner.
              Container(
                padding: AppSpacing.card,
                decoration: BoxDecoration(
                  color: vs.successTint,
                  borderRadius: AppRadius.brLg,
                  border: Border.all(color: vs.success),
                ),
                child: Row(
                  children: [
                    Icon(Icons.verified_rounded, color: vs.success),
                    AppSpacing.hGapMd,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.l10n.kycIdentityVerified,
                              style: AppTypography.titleMedium),
                          Text(
                              context.l10n.kycCibilScore('${c.score}') +
                                  (c.band.isNotEmpty ? ' · ${c.band}' : ''),
                              style: AppTypography.bodyMedium
                                  .copyWith(color: vs.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              AppSpacing.vGapLg,
              Text(context.l10n.kycStep2Documents,
                  style: AppTypography.labelMedium
                      .copyWith(color: vs.textSecondary)),
              AppSpacing.vGapXs,
              Text(context.l10n.kycDocsIntro,
                  style:
                      AppTypography.bodySmall.copyWith(color: vs.textSecondary)),
              AppSpacing.vGapMd,
              _DocUpload(
                label: context.l10n.kycAadhaarFront,
                icon: Icons.credit_card_rounded,
                path: _aadhaarFrontPath,
                onTap: () => _pick((p) => _aadhaarFrontPath = p),
              ),
              AppSpacing.vGapSm,
              _DocUpload(
                label: context.l10n.kycAadhaarBack,
                icon: Icons.flip_to_back_rounded,
                path: _aadhaarBackPath,
                onTap: () => _pick((p) => _aadhaarBackPath = p),
              ),
              AppSpacing.vGapSm,
              _DocUpload(
                label: context.l10n.kycPanFront,
                icon: Icons.badge_rounded,
                path: _panFrontPath,
                onTap: () => _pick((p) => _panFrontPath = p),
              ),
              AppSpacing.vGapSm,
              _DocUpload(
                label: context.l10n.kycPanBack,
                icon: Icons.flip_to_back_rounded,
                path: _panBackPath,
                onTap: () => _pick((p) => _panBackPath = p),
              ),
            ],
          ),
        ),
        _bottomBar(
          child: VSButton(
            label: context.l10n.kycSubmitForVerification,
            isLoading: _busy,
            onPressed: (_busy || !_docsValid) ? null : _submitDocs,
          ),
        ),
      ],
    );
  }

  // ── Done ──
  Widget _doneView(VSColors vs) {
    final c = _check!;
    return ListView(
      padding: AppSpacing.screen,
      children: [
        AppSpacing.vGapLg,
        Icon(Icons.verified_rounded, color: vs.success, size: 56),
        AppSpacing.vGapMd,
        Text(context.l10n.kycApplicationSubmitted,
            style: AppTypography.headlineSmall, textAlign: TextAlign.center),
        AppSpacing.vGapSm,
        Text(context.l10n.kycApplicationSubmittedBody,
            style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
            textAlign: TextAlign.center),
        AppSpacing.vGapXl,
        Container(
          padding: const EdgeInsets.symmetric(
              vertical: AppSpacing.xl, horizontal: AppSpacing.lg),
          decoration: BoxDecoration(
            gradient: AppColors.creditGradient,
            borderRadius: AppRadius.brXl,
            boxShadow: AppShadows.glow(AppColors.trustBlue),
          ),
          child: Column(
            children: [
              Text(context.l10n.kycYourCibilScore,
                  style: AppTypography.labelLarge
                      .copyWith(color: AppColors.white.withValues(alpha: 0.9))),
              AppSpacing.vGapSm,
              Text('${c.score}',
                  style:
                      AppTypography.displayLarge.copyWith(color: AppColors.white)),
              if (c.band.isNotEmpty)
                Text(c.band,
                    style: AppTypography.titleMedium
                        .copyWith(color: AppColors.white)),
            ],
          ),
        ),
        AppSpacing.vGapXl,
        VSButton(
            label: context.l10n.commonDone,
            onPressed: () => Navigator.of(context).pop()),
      ],
    );
  }

  Widget _bottomBar({required Widget child}) {
    final vs = context.vsColors;
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: vs.border)),
      ),
      child: SafeArea(minimum: AppSpacing.screen, child: child),
    );
  }
}

/// Uppercases input as it's typed (for the PAN field).
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: AppTypography.titleMedium);
}

class _DocUpload extends StatelessWidget {
  const _DocUpload({
    required this.label,
    required this.icon,
    required this.path,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final String? path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final has = path != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: has ? vs.successTint : context.colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: has ? vs.success : vs.border),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: has
                  ? Image.file(File(path!), width: 48, height: 48, fit: BoxFit.cover)
                  : Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      color: vs.brandTint,
                      child: Icon(icon, color: vs.brand),
                    ),
            ),
            AppSpacing.hGapMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTypography.bodyMedium),
                  Text(
                      has
                          ? context.l10n.kycTapToChange
                          : context.l10n.kycTapToUpload,
                      style:
                          AppTypography.bodySmall.copyWith(color: vs.textSecondary)),
                ],
              ),
            ),
            Icon(
              has ? Icons.check_circle_rounded : Icons.upload_rounded,
              color: has ? vs.success : vs.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsentTile extends StatelessWidget {
  const _ConsentTile({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: vs.brand,
              visualDensity: VisualDensity.compact,
            ),
            AppSpacing.hGapSm,
            Expanded(
              child: Text(
                context.l10n.kycConsentText,
                style: AppTypography.bodySmall.copyWith(color: vs.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
