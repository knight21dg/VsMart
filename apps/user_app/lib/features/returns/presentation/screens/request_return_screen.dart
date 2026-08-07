import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/image_pick_helper.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../data/returns_data.dart';
import '../providers/returns_providers.dart';

/// A photo the customer attached, held in memory until the form is submitted.
class _PickedPhoto {
  const _PickedPhoto({
    required this.bytes,
    required this.filename,
    required this.path,
  });

  final Uint8List bytes;
  final String filename;

  /// Local file path, used only for the thumbnail preview.
  final String path;
}

/// Localized display label for a canonical (English) return reason value.
/// The English value in [_RequestReturnScreenState._reasons] is what gets sent
/// to the backend; only the displayed text is translated.
String _reasonLabel(AppLocalizations l10n, String reason) => switch (reason) {
      'Damaged item' => l10n.returnReasonDamaged,
      'Wrong item' => l10n.returnReasonWrong,
      'Quality issue' => l10n.returnReasonQuality,
      'Changed my mind' => l10n.returnReasonChangedMind,
      _ => l10n.returnReasonOther,
    };

/// Return / refund request form for a delivered order. Submits to
/// `/orders/{orderCode}/returns`; on success it refreshes the returns list and
/// pops back. Mirrors [RaiseTicketScreen]'s structure.
class RequestReturnScreen extends ConsumerStatefulWidget {
  const RequestReturnScreen({super.key, required this.orderCode});

  final String orderCode;

  @override
  ConsumerState<RequestReturnScreen> createState() =>
      _RequestReturnScreenState();
}

class _RequestReturnScreenState extends ConsumerState<RequestReturnScreen> {
  static const _reasons = [
    'Damaged item',
    'Wrong item',
    'Quality issue',
    'Changed my mind',
    'Other',
  ];
  static const _maxDescription = 500;

  /// Enough to show the item from a few angles without making the upload heavy
  /// on a field connection.
  static const _maxPhotos = 5;

  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();

  String? _reason;
  int _descriptionLength = 0;
  bool _submitting = false;
  final List<_PickedPhoto> _photos = [];

  @override
  void initState() {
    super.initState();
    _description.addListener(_onDescriptionChanged);
  }

  @override
  void dispose() {
    _description
      ..removeListener(_onDescriptionChanged)
      ..dispose();
    super.dispose();
  }

  void _onDescriptionChanged() {
    final length = _description.text.characters.length;
    if (length != _descriptionLength) {
      setState(() => _descriptionLength = length);
    }
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= _maxPhotos) {
      context.showSnack(context.l10n.returnRequestPhotoLimit(_maxPhotos),
          isError: true);
      return;
    }
    final picked = await pickImageFromSource(context);
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() => _photos.add(_PickedPhoto(
          bytes: bytes,
          filename: picked.name.isNotEmpty ? picked.name : 'return.jpg',
          path: picked.path,
        )));
  }

  Future<void> _submit() async {
    context.hideKeyboard();
    if (!_formKey.currentState!.validate() || _submitting) return;
    // Photos are the evidence the pickup agent inspects against at the door,
    // so the backend rejects a return without one. Catch it here so the
    // customer isn't bounced after a round trip.
    if (_photos.isEmpty) {
      context.showSnack(context.l10n.returnRequestPhotoRequired, isError: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      final result = await ref.read(returnsDataSourceProvider).create(
            orderCode: widget.orderCode,
            reason: _reason ?? 'Other',
            description: _description.text.trim(),
            photos: [
              for (final p in _photos)
                ReturnPhotoUpload(bytes: p.bytes, filename: p.filename),
            ],
          );
      if (!mounted) return;
      if (result.ok) {
        ref.invalidate(returnsProvider);
        context.showSnack(result.message);
        context.pop();
      } else {
        setState(() => _submitting = false);
        context.showSnack(result.message, isError: true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      context.showSnack(context.l10n.returnRequestError, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: VSAppBar(title: l10n.returnRequestTitle),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: AppSpacing.screen,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l10n.returnRequestOrderLabel,
                                style: AppTypography.labelLarge),
                            AppSpacing.vGapSm,
                            Text(
                              widget.orderCode.isEmpty
                                  ? '—'
                                  : widget.orderCode,
                              style: AppTypography.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      AppSpacing.vGapLg,
                      _SectionCard(
                        child: _DropdownField(
                          label: l10n.returnRequestReasonLabel,
                          required: true,
                          hint: l10n.returnRequestSelectReason,
                          value: _reason,
                          items: _reasons,
                          itemLabel: (v) => _reasonLabel(l10n, v),
                          onChanged: (v) => setState(() => _reason = v),
                          // NB: field name kept English — Validators.required
                          // builds an English "<field> is required" template
                          // (validators.dart is shared and not localized).
                          validator: (v) =>
                              Validators.required(v, field: 'Reason'),
                        ),
                      ),
                      AppSpacing.vGapLg,
                      _SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(l10n.returnRequestDescriptionLabel,
                                    style: AppTypography.labelLarge),
                                const Spacer(),
                                Text(
                                  '$_descriptionLength/$_maxDescription',
                                  style: AppTypography.bodySmall.copyWith(
                                    color: context.vsColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            AppSpacing.vGapSm,
                            VSTextField(
                              controller: _description,
                              hint: l10n.returnRequestDescriptionHint,
                              maxLines: 5,
                              maxLength: _maxDescription,
                            ),
                          ],
                        ),
                      ),
                      AppSpacing.vGapLg,
                      _SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _RequiredLabel(l10n.returnRequestPhotosLabel),
                            AppSpacing.vGapSm,
                            Text(
                              l10n.returnRequestPhotosHint,
                              style: AppTypography.bodySmall.copyWith(
                                color: context.vsColors.textSecondary,
                              ),
                            ),
                            AppSpacing.vGapMd,
                            _PhotoPicker(
                              photos: _photos,
                              maxPhotos: _maxPhotos,
                              onAdd: _submitting ? null : _addPhoto,
                              onRemove: _submitting
                                  ? null
                                  : (i) => setState(() => _photos.removeAt(i)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _BottomBar(onSubmit: _submit, isLoading: _submitting),
          ],
        ),
      ),
    );
  }
}

/// Thumbnail strip of attached photos plus an "add" tile. At least one photo is
/// required, so the add tile is always the last cell until the cap is reached.
class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({
    required this.photos,
    required this.maxPhotos,
    required this.onAdd,
    required this.onRemove,
  });

  final List<_PickedPhoto> photos;
  final int maxPhotos;
  final VoidCallback? onAdd;
  final void Function(int index)? onRemove;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        for (var i = 0; i < photos.length; i++)
          SizedBox(
            width: 84,
            height: 84,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: AppRadius.brMd,
                    child: Image.file(
                      File(photos[i].path),
                      fit: BoxFit.cover,
                      // The bytes are already in memory; if the temp file is
                      // gone the thumbnail must not take the form down.
                      errorBuilder: (_, __, ___) => Image.memory(
                        photos[i].bytes,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: onRemove == null ? null : () => onRemove!(i),
                    child: Tooltip(
                      message: context.l10n.returnRequestRemovePhoto,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded,
                            size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (photos.length < maxPhotos)
          GestureDetector(
            onTap: onAdd,
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                borderRadius: AppRadius.brMd,
                border: Border.all(color: vs.border),
                color: context.colors.surface,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_outlined,
                      size: 20, color: vs.textSecondary),
                  AppSpacing.vGapXs,
                  Text(
                    context.l10n.returnRequestAddPhoto,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall
                        .copyWith(color: vs.textSecondary),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// White rounded container that groups a labeled form section.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: context.vsColors.border),
      ),
      child: child,
    );
  }
}

/// A label with a trailing red asterisk to mark required fields.
class _RequiredLabel extends StatelessWidget {
  const _RequiredLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: label,
        style: AppTypography.labelLarge,
        children: [
          TextSpan(
            text: ' *',
            style: AppTypography.labelLarge.copyWith(color: AppColors.error),
          ),
        ],
      ),
    );
  }
}

/// Theme-styled dropdown that matches [VSTextField]'s look.
class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
    this.itemLabel,
    this.required = false,
    this.validator,
  });

  final String label;
  final String hint;
  final String? value;
  final List<String> items;

  /// Optional display mapping for each item. When null the item value is shown
  /// verbatim; used to translate labels while keeping stable backend values.
  final String Function(String value)? itemLabel;
  final ValueChanged<String?> onChanged;
  final bool required;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (required)
          _RequiredLabel(label)
        else
          Text(label, style: AppTypography.labelLarge),
        AppSpacing.vGapSm,
        DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          hint: Text(
            hint,
            style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
          ),
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: vs.textSecondary),
          style:
              AppTypography.bodyMedium.copyWith(color: context.colors.onSurface),
          validator: validator,
          items: [
            for (final item in items)
              DropdownMenuItem(
                value: item,
                child: Text(itemLabel?.call(item) ?? item),
              ),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Sticky bottom action bar with Cancel and Submit buttons.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.onSubmit, required this.isLoading});

  final VoidCallback onSubmit;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.screen,
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: context.vsColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: VSOutlinedButton(
              label: context.l10n.commonCancel,
              onPressed: isLoading ? null : () => context.pop(),
            ),
          ),
          AppSpacing.hGapMd,
          Expanded(
            flex: 2,
            child: VSButton(
              label: context.l10n.returnRequestSubmit,
              isLoading: isLoading,
              onPressed: onSubmit,
            ),
          ),
        ],
      ),
    );
  }
}
