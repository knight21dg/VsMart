import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/ui.dart';
import '../../dashboard/presentation/dashboard_providers.dart';

/// First-login (and any-login-until-completed) photo capture: the same face
/// that ends up as [AgentProfile.avatarUrl], which the backend seeds onto
/// every OrderTracking row it creates for this agent from then on — this is
/// how a customer recognises their delivery/collection agent on the tracking
/// screen. Shown by `_AuthGate` whenever `agentProfileProvider.avatarUrl` is
/// empty; "Skip for now" lets an agent through without blocking them
/// indefinitely (camera permission issues, a broken lens, whatever), but
/// they'll see this again next login until it's done.
class FaceCaptureScreen extends ConsumerStatefulWidget {
  const FaceCaptureScreen({super.key, required this.onDone});

  /// Called once the agent either uploads a photo or explicitly skips.
  final VoidCallback onDone;

  @override
  ConsumerState<FaceCaptureScreen> createState() => _FaceCaptureScreenState();
}

class _FaceCaptureScreenState extends ConsumerState<FaceCaptureScreen> {
  final _picker = ImagePicker();
  XFile? _shot;
  bool _busy = false;

  Future<void> _takePhoto() async {
    XFile? shot;
    try {
      shot = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 80,
        maxWidth: 1200,
      );
      if (shot == null) {
        final lost = await _picker.retrieveLostData();
        if (!lost.isEmpty) shot = lost.file;
      }
    } catch (e) {
      if (mounted) showToast(context, 'Camera failed: $e', error: true);
      return;
    }
    if (shot == null) return; // agent backed out of the camera — stay on this screen
    setState(() => _shot = shot);
  }

  Future<void> _confirm() async {
    final shot = _shot;
    if (shot == null || _busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await File(shot.path).readAsBytes();
      await ref.read(dashboardRepoProvider).uploadAvatar(
            bytes: bytes,
            filename: shot.name.isNotEmpty ? shot.name : 'agent_face.jpg',
          );
      ref.invalidate(agentProfileProvider);
      if (mounted) {
        showToast(context, 'Photo saved — customers will now see your face.');
        widget.onDone();
      }
    } catch (e) {
      if (mounted) {
        showApiError(context, e, fallback: 'Could not upload your photo.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgentColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 24),
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AgentColors.brand.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.face_retouching_natural_rounded,
                    size: 44, color: AgentColors.brand),
              ),
              const SizedBox(height: 20),
              const Text('Add your photo',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text(
                'Customers see this photo on their delivery tracking screen '
                'so they can recognise you at the door. Take a clear photo of '
                'your face.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AgentColors.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: Center(
                  child: _shot == null
                      ? _EmptyFrame(onTap: _takePhoto)
                      : _PreviewFrame(path: _shot!.path),
                ),
              ),
              const SizedBox(height: 16),
              if (_shot == null)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _takePhoto,
                    icon: const Icon(Icons.camera_alt_rounded),
                    label: const Text('Open camera'),
                  ),
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => setState(() => _shot = null),
                        child: const Text('Retake'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null : _confirm,
                        child: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Use this photo'),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              TextButton(
                onPressed: _busy ? null : widget.onDone,
                child: const Text("Skip for now",
                    style: TextStyle(color: AgentColors.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyFrame extends StatelessWidget {
  const _EmptyFrame({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(140),
      child: Container(
        width: 220,
        height: 220,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AgentColors.surface,
          border: Border.all(
              color: AgentColors.border, width: 1.5, style: BorderStyle.solid),
        ),
        child: const Icon(Icons.person_outline_rounded,
            size: 96, color: AgentColors.border),
      ),
    );
  }
}

class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      height: 220,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AgentColors.brand, width: 2.5),
        image: DecorationImage(
          image: FileImage(File(path)),
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
