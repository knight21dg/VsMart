import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/app_error_presenter.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../kyc/data/kyc_status_data.dart';
import '../providers/verification_providers.dart';

/// Lifecycle of the GPS capture shown in the location card.
enum _GpsPhase {
  /// Acquiring permission / a position fix.
  loading,

  /// A real device position was captured.
  captured,

  /// Location permission was denied (re-askable).
  denied,

  /// Permission is permanently denied — must be enabled in system settings.
  deniedForever,

  /// The device location service is switched off.
  serviceOff,

  /// GPS was granted but a fix could not be obtained.
  error,
}

/// Residence verification: capture a photo of the customer's home, capture the
/// REAL device GPS coordinates, then submit both to the KYC backend.
class ResidenceVerificationScreen extends ConsumerStatefulWidget {
  const ResidenceVerificationScreen({super.key});

  @override
  ConsumerState<ResidenceVerificationScreen> createState() =>
      _ResidenceVerificationScreenState();
}

class _ResidenceVerificationScreenState
    extends ConsumerState<ResidenceVerificationScreen> {
  File? _photo;
  double? _latitude;
  double? _longitude;
  _GpsPhase _gps = _GpsPhase.loading;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _captureLocation();
  }

  /// Acquires the device's real coordinates via [LocationService], mapping the
  /// permission/service outcome onto a [_GpsPhase] the UI can react to.
  Future<void> _captureLocation() async {
    setState(() => _gps = _GpsPhase.loading);
    final service = ref.read(locationServiceProvider);

    final permission = await service.checkPermission();
    if (!mounted) return;
    switch (permission) {
      case LocationPermissionState.deniedForever:
        setState(() => _gps = _GpsPhase.deniedForever);
        return;
      case LocationPermissionState.serviceOff:
        setState(() => _gps = _GpsPhase.serviceOff);
        return;
      case LocationPermissionState.denied:
        setState(() => _gps = _GpsPhase.denied);
        return;
      case LocationPermissionState.granted:
        break;
    }

    final position = await service.getCurrentPosition();
    if (!mounted) return;
    if (position == null) {
      setState(() => _gps = _GpsPhase.error);
      return;
    }
    setState(() {
      _latitude = position.latitude;
      _longitude = position.longitude;
      _gps = _GpsPhase.captured;
    });
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await ImagePicker()
          .pickImage(source: source, maxWidth: 1280, imageQuality: 80);
      if (file != null && mounted) {
        setState(() => _photo = File(file.path));
        context.showSnack(context.l10n.verificationResidencePhotoAttached);
      }
    } catch (_) {
      if (mounted) {
        context.showSnack(context.l10n.verificationCameraGalleryError);
      }
    }
  }

  Future<void> _submit() async {
    context.hideKeyboard();
    final photo = _photo;
    if (photo == null) {
      context.showSnack(context.l10n.verificationAddResidencePhoto,
          isError: true);
      return;
    }
    if (_gps != _GpsPhase.captured || _latitude == null || _longitude == null) {
      context.showSnack(
        context.l10n.verificationCaptureLocationFirst,
        isError: true,
      );
      return;
    }

    setState(() => _submitting = true);
    final result =
        await ref.read(verificationRepositoryProvider).submitResidence(
              photoPath: photo.path,
              latitude: _latitude!,
              longitude: _longitude!,
            );
    if (!mounted) return;
    setState(() => _submitting = false);

    result.fold(
      (failure) => presentFailure(context, ref, failure, onRetry: _submit),
      (_) {
        // Record the residence proof in the draft so it counts toward the
        // final submit gate ([VerificationDraft.isReadyToSubmit]) and shows in
        // the review summary — the backend already persisted the photo/coords.
        ref.read(verificationControllerProvider.notifier).setResidence(
              photoPath: photo.path,
              latitude: _latitude!,
              longitude: _longitude!,
            );
        // Re-read the real KYC standing so the dashboard / details screens
        // reflect the residence document the backend just recorded.
        ref.invalidate(verificationStatusProvider);
        ref.invalidate(kycStatusProvider);
        context.showSnack(context.l10n.verificationResidenceSubmitted);
        // Residence is the last document — go straight to review & submit.
        // (The credit application is no longer part of identity verification.)
        context.pushNamed(RouteNames.verificationReview);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;

    return Scaffold(
      appBar: VSAppBar(title: context.l10n.verifyResidence),
      body: ListView(
        padding: AppSpacing.screen,
        children: [
          Text(
            context.l10n.verificationResidenceIntro,
            style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
          ),
          AppSpacing.vGapLg,
          _UploadBox(
            photo: _photo,
            onCapture: () => _pick(ImageSource.camera),
            onGallery: () => _pick(ImageSource.gallery),
          ),
          AppSpacing.vGapLg,
          const _SampleImageCard(),
          AppSpacing.vGapLg,
          const _RequirementsCard(),
          AppSpacing.vGapLg,
          _LocationCard(
            phase: _gps,
            latitude: _latitude,
            longitude: _longitude,
            onRetry: _captureLocation,
            onOpenAppSettings: () =>
                ref.read(locationServiceProvider).openAppSettings(),
            onOpenLocationSettings: () =>
                ref.read(locationServiceProvider).openLocationSettings(),
          ),
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
            label: context.l10n.verifyUploadContinue,
            icon: Icons.cloud_upload_outlined,
            isLoading: _submitting,
            onPressed:
                (_photo != null && _gps == _GpsPhase.captured && !_submitting)
                    ? _submit
                    : null,
          ),
        ),
      ),
    );
  }
}

/// Dashed, brand-tinted upload area with capture / gallery actions. The picked
/// photo is owned by the parent screen so submission can read it.
class _UploadBox extends StatelessWidget {
  const _UploadBox({
    required this.photo,
    required this.onCapture,
    required this.onGallery,
  });

  final File? photo;
  final VoidCallback onCapture;
  final VoidCallback onGallery;

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
          if (photo != null)
            ClipRRect(
              borderRadius: AppRadius.brMd,
              child: Image.file(
                photo!,
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
            label: photo == null ? 'Take Photo' : 'Retake Photo',
            icon: Icons.camera_alt_outlined,
            onPressed: onCapture,
          ),
          AppSpacing.vGapMd,
          VSOutlinedButton(
            label: context.l10n.verifyChooseGallery,
            icon: Icons.photo_library_outlined,
            onPressed: onGallery,
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
              Text(context.l10n.verificationSampleApprovedImage,
                  style: AppTypography.titleMedium),
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
                          context.l10n.verificationIdeal,
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
          Text(context.l10n.verifyPhotoRequirements,
              style: AppTypography.titleMedium),
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

/// "Location Verification" card. Renders the real captured latitude/longitude
/// once GPS resolves, or a permission/error state with a recovery action — it
/// never shows a fake "captured" chip.
class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.phase,
    required this.latitude,
    required this.longitude,
    required this.onRetry,
    required this.onOpenAppSettings,
    required this.onOpenLocationSettings,
  });

  final _GpsPhase phase;
  final double? latitude;
  final double? longitude;
  final VoidCallback onRetry;
  final VoidCallback onOpenAppSettings;
  final VoidCallback onOpenLocationSettings;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(context.l10n.verifyLocation,
                  style: AppTypography.titleMedium),
              _statusChip(context),
            ],
          ),
          AppSpacing.vGapMd,
          _body(context),
        ],
      ),
    );
  }

  Widget _statusChip(BuildContext context) {
    final vs = context.vsColors;
    final (bg, fg, icon, label) = switch (phase) {
      _GpsPhase.captured => (
          vs.successTint,
          vs.success,
          Icons.check_circle,
          'GPS Captured',
        ),
      _GpsPhase.loading => (
          vs.brandTint,
          vs.brand,
          Icons.gps_fixed,
          'Locating…',
        ),
      _ => (
          vs.dangerTint,
          vs.danger,
          Icons.location_off,
          'Not captured',
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.brPill),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          AppSpacing.hGapSm,
          Text(label, style: AppTypography.labelSmall.copyWith(color: fg)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (phase) {
      case _GpsPhase.loading:
        return _statusBox(
          context,
          icon: Icons.my_location_outlined,
          message: 'Capturing your current location…',
          showSpinner: true,
        );
      case _GpsPhase.captured:
        return _captured(context);
      case _GpsPhase.denied:
        return _statusBox(
          context,
          icon: Icons.location_disabled_outlined,
          message:
              'Location permission is needed to confirm your residence. Grant '
              'access to continue.',
          actionLabel: 'Grant Permission',
          onAction: onRetry,
        );
      case _GpsPhase.deniedForever:
        return _statusBox(
          context,
          icon: Icons.location_disabled_outlined,
          message:
              'Location permission is turned off. Enable it in Settings to '
              'capture your residence coordinates.',
          actionLabel: 'Open Settings',
          onAction: onOpenAppSettings,
        );
      case _GpsPhase.serviceOff:
        return _statusBox(
          context,
          icon: Icons.gps_off_outlined,
          message:
              'Device location is switched off. Turn it on to capture your '
              'residence coordinates.',
          actionLabel: 'Turn On Location',
          onAction: onOpenLocationSettings,
        );
      case _GpsPhase.error:
        return _statusBox(
          context,
          icon: Icons.error_outline_rounded,
          message: "Couldn't capture your location. Please try again.",
          actionLabel: 'Retry',
          onAction: onRetry,
        );
    }
  }

  Widget _captured(BuildContext context) {
    final vs = context.vsColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        _CoordinateTile(
          icon: Icons.my_location_outlined,
          label: context.l10n.verificationLatitude,
          value: _fmtLat(latitude!),
        ),
        AppSpacing.vGapSm,
        _CoordinateTile(
          icon: Icons.explore_outlined,
          label: context.l10n.verificationLongitude,
          value: _fmtLng(longitude!),
        ),
      ],
    );
  }

  /// Compact status box with an icon, message and optional recovery action —
  /// reused for the loading / permission / error phases.
  Widget _statusBox(
    BuildContext context, {
    required IconData icon,
    required String message,
    bool showSpinner = false,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final vs = context.vsColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: vs.brandTint.withValues(alpha: 0.4),
        borderRadius: AppRadius.brMd,
      ),
      child: Column(
        children: [
          if (showSpinner)
            const SizedBox(
              height: 28,
              width: 28,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            )
          else
            Icon(icon, size: 32, color: vs.textSecondary),
          AppSpacing.vGapMd,
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(color: vs.textSecondary),
          ),
          if (actionLabel != null && onAction != null) ...[
            AppSpacing.vGapMd,
            VSOutlinedButton(
              label: actionLabel,
              icon: Icons.location_searching_rounded,
              isExpanded: false,
              onPressed: onAction,
            ),
          ],
        ],
      ),
    );
  }

  String _fmtLat(double v) =>
      '${v.abs().toStringAsFixed(6)}° ${v >= 0 ? 'N' : 'S'}';

  String _fmtLng(double v) =>
      '${v.abs().toStringAsFixed(6)}° ${v >= 0 ? 'E' : 'W'}';
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
