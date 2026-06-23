import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';

/// Residence verification: capture a photo of the customer's home, review the
/// sample / requirements, confirm GPS-captured coordinates, then submit.
class ResidenceVerificationScreen extends StatelessWidget {
  const ResidenceVerificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;

    return Scaffold(
      appBar: const VSAppBar(title: 'Residence Verification'),
      body: ListView(
        padding: AppSpacing.screen,
        children: [
          Text(
            'Please upload a clear photo of your residence to verify your '
            'address for faster processing and secure deliveries.',
            style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
          ),
          AppSpacing.vGapLg,
          const _UploadBox(),
          AppSpacing.vGapLg,
          const _SampleImageCard(),
          AppSpacing.vGapLg,
          const _RequirementsCard(),
          AppSpacing.vGapLg,
          const _LocationCard(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
          border: Border(top: BorderSide(color: vs.border)),
        ),
        child: SafeArea(
          minimum: AppSpacing.screen,
          child: VSButton(
            label: 'Upload & Continue',
            icon: Icons.cloud_upload_outlined,
            onPressed: () {
              context.showSnack('Residence verification submitted.');
              context.hideKeyboard();
            },
          ),
        ),
      ),
    );
  }
}

/// Dashed, brand-tinted upload area with capture / gallery actions.
class _UploadBox extends StatefulWidget {
  const _UploadBox();

  @override
  State<_UploadBox> createState() => _UploadBoxState();
}

class _UploadBoxState extends State<_UploadBox> {
  File? _photo;

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await ImagePicker()
          .pickImage(source: source, maxWidth: 1280, imageQuality: 80);
      if (file != null && mounted) {
        setState(() => _photo = File(file.path));
        context.showSnack('Residence photo attached.');
      }
    } catch (_) {
      if (mounted) context.showSnack('Could not access the camera/gallery.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
      ),
      child: Column(
        children: [
          if (_photo != null)
            ClipRRect(
              borderRadius: AppRadius.brMd,
              child: Image.file(
                _photo!,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            )
          else
            Container(
              height: 64,
              width: 64,
              decoration: const BoxDecoration(
                color: AppColors.vsGreen,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add_a_photo_outlined,
                color: AppColors.white,
                size: 28,
              ),
            ),
          AppSpacing.vGapLg,
          VSButton(
            label: _photo == null ? 'Take Photo' : 'Retake Photo',
            icon: Icons.camera_alt_outlined,
            onPressed: () => _pick(ImageSource.camera),
          ),
          AppSpacing.vGapMd,
          VSOutlinedButton(
            label: 'Choose From Gallery',
            icon: Icons.photo_library_outlined,
            onPressed: () => _pick(ImageSource.gallery),
          ),
        ],
      ),
    );
  }
}

/// "Sample Approved Image" card with an illustrative tile and an "Ideal" badge.
class _SampleImageCard extends StatelessWidget {
  const _SampleImageCard();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: vs.trust),
              AppSpacing.hGapSm,
              Text('Sample Approved Image', style: AppTypography.titleMedium),
            ],
          ),
          AppSpacing.vGapMd,
          ClipRRect(
            borderRadius: AppRadius.brMd,
            child: Stack(
              children: [
                Container(
                  height: 140,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: vs.brandTint,
                    borderRadius: AppRadius.brMd,
                  ),
                  child: Icon(
                    Icons.home_outlined,
                    size: 56,
                    color: vs.brand,
                  ),
                ),
                Positioned(
                  right: AppSpacing.sm,
                  bottom: AppSpacing.sm,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: const BoxDecoration(
                      color: AppColors.vsGreen,
                      borderRadius: AppRadius.brPill,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.check_circle,
                          size: 14,
                          color: AppColors.white,
                        ),
                        AppSpacing.hGapSm,
                        Text(
                          'Ideal',
                          style: AppTypography.labelSmall
                              .copyWith(color: AppColors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Bullet list of photo requirements.
class _RequirementsCard extends StatelessWidget {
  const _RequirementsCard();

  static const List<(IconData, String, bool)> _items = [
    (Icons.home_work_outlined, 'House structure should be clearly visible', true),
    (Icons.wb_sunny_outlined, 'Ensure photo is taken in daylight', true),
    (Icons.location_on_outlined, 'Address plate or area should be visible', true),
    (Icons.block, 'Avoid blurry or low-light photos', false),
  ];

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Photo Requirements', style: AppTypography.titleMedium),
          AppSpacing.vGapMd,
          for (final (icon, label, ok) in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: ok ? vs.brand : vs.danger,
                  ),
                  AppSpacing.hGapSm,
                  Expanded(
                    child: Text(
                      label,
                      style: AppTypography.bodySmall
                          .copyWith(color: vs.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// "Location Verification" card with a GPS-captured chip, map illustration and
/// read-only latitude / longitude fields.
class _LocationCard extends StatelessWidget {
  const _LocationCard();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Location Verification',
                  style: AppTypography.titleMedium),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: vs.successTint,
                  borderRadius: AppRadius.brPill,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 14, color: vs.success),
                    AppSpacing.hGapSm,
                    Text(
                      'GPS Captured',
                      style:
                          AppTypography.labelSmall.copyWith(color: vs.success),
                    ),
                  ],
                ),
              ),
            ],
          ),
          AppSpacing.vGapMd,
          Container(
            height: 140,
            width: double.infinity,
            decoration: BoxDecoration(
              color: vs.brandTint,
              borderRadius: AppRadius.brMd,
            ),
            child: Icon(Icons.location_pin, size: 48, color: vs.brand),
          ),
          AppSpacing.vGapMd,
          const _CoordinateTile(
            icon: Icons.my_location_outlined,
            label: 'Latitude',
            value: '34.0522° N',
          ),
          AppSpacing.vGapSm,
          const _CoordinateTile(
            icon: Icons.explore_outlined,
            label: 'Longitude',
            value: '118.2437° W',
          ),
        ],
      ),
    );
  }
}

/// Single read-only coordinate row inside the location card.
class _CoordinateTile extends StatelessWidget {
  const _CoordinateTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: vs.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: vs.textSecondary),
          AppSpacing.hGapMd,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style:
                    AppTypography.labelSmall.copyWith(color: vs.textSecondary),
              ),
              AppSpacing.vGapXs,
              Text(value, style: AppTypography.labelLarge),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shared white rounded card container used by the section cards above.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

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
      child: child,
    );
  }
}
