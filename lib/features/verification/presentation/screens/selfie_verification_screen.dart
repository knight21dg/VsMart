import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../providers/verification_providers.dart';

/// Step 2 of verification: a live selfie. Captures from the front camera, saves
/// the path to the draft immediately, and supports retake / permission / error
/// states.
class SelfieVerificationScreen extends ConsumerStatefulWidget {
  const SelfieVerificationScreen({super.key});

  @override
  ConsumerState<SelfieVerificationScreen> createState() =>
      _SelfieVerificationScreenState();
}

class _SelfieVerificationScreenState
    extends ConsumerState<SelfieVerificationScreen> {
  CameraController? _camera;
  String? _capturedPath;
  bool _denied = false;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = ref.read(verificationControllerProvider).selfiePath;
    if (existing != null) {
      _capturedPath = existing;
    } else {
      _init();
    }
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _error = null;
      _ready = false;
    });
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) setState(() => _denied = true);
      return;
    }
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _ready = true;
        _denied = false;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Camera is unavailable');
    }
  }

  Future<void> _capture() async {
    final c = _camera;
    if (c == null || !c.value.isInitialized) return;
    try {
      final file = await c.takePicture();
      final path =
          await ref.read(imageCompressionServiceProvider).compress(file.path);
      ref.read(verificationControllerProvider.notifier).setSelfie(path);
      ref.read(analyticsServiceProvider).selfieCaptured();
      if (mounted) setState(() => _capturedPath = path);
    } catch (_) {
      if (mounted) context.showSnack('Capture failed', isError: true);
    }
  }

  void _retake() {
    setState(() => _capturedPath = null);
    _init();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const VSAppBar(title: 'Face Verification'),
      body: SafeArea(child: _content(context)),
    );
  }

  Widget _content(BuildContext context) {
    if (_capturedPath != null) return _preview(context, _capturedPath!);
    if (_denied) return _permission(context);
    if (_error != null) return _errorState(context, _error!);
    if (!_ready) return const VSLoadingView(message: 'Starting camera…');
    return _cameraView(context);
  }

  Widget _cameraView(BuildContext context) {
    final vs = context.vsColors;
    return Column(
      children: [
        AppSpacing.vGapSm,
        Text('Ensure your face is clearly visible.',
            style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary)),
        AppSpacing.vGapLg,
        Expanded(
          child: Padding(
            padding: AppSpacing.screenHorizontal,
            child: ClipRRect(
              borderRadius: AppRadius.brXl,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(_camera!),
                  Center(
                    child: Container(
                      width: 220,
                      height: 280,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(140),
                        border: Border.all(color: vs.brand, width: 3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Padding(
          padding: AppSpacing.screen,
          child: _SelfieChecklist(),
        ),
        Padding(
          padding: AppSpacing.screenHorizontal,
          child: VSButton(
            label: 'Capture',
            icon: Icons.photo_camera_rounded,
            onPressed: _capture,
          ),
        ),
        AppSpacing.vGapLg,
      ],
    );
  }

  Widget _preview(BuildContext context, String path) {
    final vs = context.vsColors;
    return Column(
      children: [
        AppSpacing.vGapLg,
        Expanded(
          child: Padding(
            padding: AppSpacing.screenHorizontal,
            child: ClipRRect(
              borderRadius: AppRadius.brXl,
              child: File(path).existsSync()
                  ? Image.file(File(path), fit: BoxFit.cover, width: double.infinity)
                  : Container(color: vs.brandTint),
            ),
          ),
        ),
        Padding(
          padding: AppSpacing.screen,
          child: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: vs.success, size: 18),
              AppSpacing.hGapSm,
              Text('Selfie captured', style: AppTypography.bodyMedium),
            ],
          ),
        ),
        Padding(
          padding: AppSpacing.screenHorizontal,
          child: Row(
            children: [
              Expanded(
                child: VSOutlinedButton(label: 'Retake', onPressed: _retake),
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: VSButton(
                  label: 'Continue',
                  onPressed: () =>
                      context.pushNamed(RouteNames.creditApplication),
                ),
              ),
            ],
          ),
        ),
        AppSpacing.vGapLg,
      ],
    );
  }

  Widget _permission(BuildContext context) {
    return const VSEmptyState(
      title: 'Camera access needed',
      message:
          'Enable camera permission to capture your verification selfie.',
      icon: Icons.no_photography_rounded,
      actionLabel: 'Open Settings',
      onAction: openAppSettings,
    );
  }

  Widget _errorState(BuildContext context, String message) {
    return VSErrorView(
      message: message,
      icon: Icons.videocam_off_rounded,
      onRetry: _init,
    );
  }
}

class _SelfieChecklist extends StatelessWidget {
  const _SelfieChecklist();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    const items = [
      (Icons.remove_red_eye_outlined, 'Remove sunglasses/mask'),
      (Icons.center_focus_strong_rounded, 'Look straight at the camera'),
      (Icons.wb_sunny_outlined, 'Ensure good lighting'),
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: vs.border),
      ),
      child: Column(
        children: [
          for (final (icon, label) in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: vs.textSecondary),
                  AppSpacing.hGapSm,
                  Text(label,
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
