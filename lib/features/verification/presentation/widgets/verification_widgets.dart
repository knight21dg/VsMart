import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';

/// Upload lifecycle for a single document card.
enum UploadState { empty, uploading, uploaded, failed }

/// Reusable document upload card with empty / uploading / uploaded / failed
/// states. Offers camera + gallery sources and retake/remove on success.
class VSUploadCard extends StatelessWidget {
  const VSUploadCard({
    super.key,
    required this.title,
    required this.state,
    this.filePath,
    this.onCapture,
    this.onPickGallery,
    this.onRetry,
    this.onRemove,
  });

  final String title;
  final UploadState state;
  final String? filePath;
  final VoidCallback? onCapture;
  final VoidCallback? onPickGallery;
  final VoidCallback? onRetry;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(
          color: switch (state) {
            UploadState.uploaded => vs.success,
            UploadState.failed => vs.danger,
            _ => vs.border,
          },
        ),
      ),
      child: switch (state) {
        UploadState.empty => _empty(context),
        UploadState.uploading => _uploading(context),
        UploadState.uploaded => _uploaded(context),
        UploadState.failed => _failed(context),
      },
    );
  }

  Widget _label(BuildContext context, {Widget? trailing}) {
    return Row(
      children: [
        Expanded(child: Text(title, style: AppTypography.titleMedium)),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _empty(BuildContext context) {
    final vs = context.vsColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(context),
        AppSpacing.vGapMd,
        Row(
          children: [
            Expanded(
              child: _SourceButton(
                icon: Icons.photo_camera_rounded,
                label: 'Camera',
                onTap: onCapture,
              ),
            ),
            AppSpacing.hGapMd,
            Expanded(
              child: _SourceButton(
                icon: Icons.photo_library_rounded,
                label: 'Gallery',
                onTap: onPickGallery,
              ),
            ),
          ],
        ),
        AppSpacing.vGapSm,
        Text('JPG or PNG, up to 5 MB',
            style: AppTypography.labelSmall.copyWith(color: vs.textSecondary)),
      ],
    );
  }

  Widget _uploading(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          height: 22,
          width: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
        AppSpacing.hGapMd,
        Expanded(child: Text('Uploading $title…', style: AppTypography.bodyMedium)),
      ],
    );
  }

  Widget _uploaded(BuildContext context) {
    final vs = context.vsColors;
    return Row(
      children: [
        ClipRRect(
          borderRadius: AppRadius.brSm,
          child: _Thumb(path: filePath),
        ),
        AppSpacing.hGapMd,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label(
                context,
                trailing: Icon(Icons.check_circle_rounded,
                    color: vs.success, size: 20),
              ),
              Text('Uploaded',
                  style:
                      AppTypography.bodySmall.copyWith(color: vs.success)),
              AppSpacing.vGapXs,
              Row(
                children: [
                  GestureDetector(
                    onTap: onCapture,
                    child: Text('Retake',
                        style: AppTypography.labelMedium
                            .copyWith(color: vs.trust)),
                  ),
                  if (onRemove != null) ...[
                    AppSpacing.hGapLg,
                    GestureDetector(
                      onTap: onRemove,
                      child: Text('Remove',
                          style: AppTypography.labelMedium
                              .copyWith(color: vs.danger)),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _failed(BuildContext context) {
    final vs = context.vsColors;
    return Row(
      children: [
        Icon(Icons.error_outline_rounded, color: vs.danger),
        AppSpacing.hGapMd,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.titleMedium),
              Text('Upload failed',
                  style: AppTypography.bodySmall.copyWith(color: vs.danger)),
            ],
          ),
        ),
        TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({this.path});
  final String? path;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    if (path != null && File(path!).existsSync()) {
      return Image.file(File(path!), height: 48, width: 48, fit: BoxFit.cover);
    }
    return Container(
      height: 48,
      width: 48,
      color: vs.brandTint,
      child: Icon(Icons.description_rounded, color: vs.brand, size: 22),
    );
  }
}

class _SourceButton extends StatelessWidget {
  const _SourceButton({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brMd,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: vs.brandTint.withValues(alpha: 0.4),
          borderRadius: AppRadius.brMd,
          border: Border.all(color: vs.border),
        ),
        child: Column(
          children: [
            Icon(icon, color: vs.brand),
            const SizedBox(height: AppSpacing.xs),
            Text(label, style: AppTypography.labelMedium),
          ],
        ),
      ),
    );
  }
}

/// Selectable requested-credit-limit card.
class VSCreditOptionCard extends StatelessWidget {
  const VSCreditOptionCard({
    super.key,
    required this.amount,
    required this.selected,
    required this.onTap,
  });

  final num amount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brLg,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? vs.brandTint : context.colors.surface,
          borderRadius: AppRadius.brLg,
          border: Border.all(
            color: selected ? vs.brand : vs.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(amount.asCurrency,
                style: AppTypography.priceMedium
                    .copyWith(color: selected ? vs.brand : null)),
            Text('limit',
                style:
                    AppTypography.labelSmall.copyWith(color: vs.textSecondary)),
          ],
        ),
      ),
    );
  }
}

/// Top-of-screen step progress used across the verification flow.
class VSVerificationProgress extends StatelessWidget {
  const VSVerificationProgress({
    super.key,
    required this.step,
    required this.total,
  });

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final progress = (step / total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Step $step of $total',
                  style: AppTypography.labelMedium
                      .copyWith(color: vs.textSecondary)),
              Text('${(progress * 100).round()}%',
                  style: AppTypography.labelMedium
                      .copyWith(color: vs.textSecondary)),
            ],
          ),
          AppSpacing.vGapSm,
          ClipRRect(
            borderRadius: AppRadius.brPill,
            child: LinearProgressIndicator(
              value: progress,
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
