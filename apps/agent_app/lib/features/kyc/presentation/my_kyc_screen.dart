import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/ui.dart';
import '../../profile/data/profile_data.dart';
import '../data/my_kyc_data.dart';

/// The agent's OWN KYC — capture documents, submit, track the decision.
///
/// The agent app shipped with only the *reviewer* side of KYC (the queue of
/// customer applications). An agent whose own verification was pending or
/// rejected saw one read-only word on their profile and had no route to fix it,
/// which is the gap the QA report records as "Agent KYC flow is missing". The
/// backend needed nothing new: `/kyc/status` and `/kyc/submit` key on
/// `request.user` and never cared what role that user has.
class MyKycScreen extends ConsumerStatefulWidget {
  const MyKycScreen({super.key});

  @override
  ConsumerState<MyKycScreen> createState() => _MyKycScreenState();
}

class _MyKycScreenState extends ConsumerState<MyKycScreen> {
  final _picker = ImagePicker();
  final _shots = <String, XFile>{};
  bool _busy = false;

  Future<void> _capture(String type) async {
    XFile? shot;
    try {
      shot = await _picker.pickImage(
        source: ImageSource.camera,
        // A selfie wants the front lens; a document wants the back one.
        preferredCameraDevice:
            type == 'selfie' ? CameraDevice.front : CameraDevice.rear,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (shot == null) {
        // Android can kill the app while the camera is open; the photo is
        // recoverable rather than lost.
        final lost = await _picker.retrieveLostData();
        if (!lost.isEmpty) shot = lost.file;
      }
    } catch (e) {
      if (mounted) showToast(context, 'Camera failed: $e', error: true);
      return;
    }
    if (shot == null) return; // backed out of the camera
    setState(() => _shots[type] = shot!);
  }

  Future<void> _pickFromGallery(String type) async {
    try {
      final shot = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (shot == null) return;
      setState(() => _shots[type] = shot);
    } catch (e) {
      if (mounted) showToast(context, 'Could not open the gallery: $e', error: true);
    }
  }

  Future<void> _submit() async {
    if (_busy || _shots.isEmpty) return;
    setState(() => _busy = true);
    try {
      final files = <String, ({List<int> bytes, String filename})>{};
      for (final entry in _shots.entries) {
        final bytes = await File(entry.value.path).readAsBytes();
        files[entry.key] = (
          bytes: bytes,
          filename: entry.value.name.isNotEmpty
              ? entry.value.name
              : '${entry.key}.jpg',
        );
      }
      await ref.read(myKycRepoProvider).submit(files);
      // The decision lands on the profile's KYC row too, so refresh both.
      ref.invalidate(myKycProvider);
      ref.invalidate(userProfileProvider);
      if (mounted) {
        setState(_shots.clear);
        showToast(context, 'Documents submitted — we\'ll review them shortly.');
      }
    } catch (e) {
      if (mounted) {
        showApiError(context, e, fallback: 'Could not submit your documents.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myKycProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('My KYC')),
      body: async.when(
        loading: () => const Loading(),
        error: (_, __) => ErrorRetry(
          message: 'Could not load your KYC status.',
          onRetry: () => ref.invalidate(myKycProvider),
        ),
        data: (kyc) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(myKycProvider),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatusCard(kyc: kyc),
              const SizedBox(height: 16),
              if (kyc.canSubmit) ...[
                const SectionHeader('Upload your documents'),
                const SizedBox(height: 8),
                for (final entry in kycDocTypes.entries)
                  _DocRow(
                    type: entry.key,
                    label: entry.value,
                    shot: _shots[entry.key],
                    alreadyUploaded: kyc.uploadedTypes.contains(entry.key),
                    enabled: !_busy,
                    onCapture: () => _capture(entry.key),
                    onGallery: () => _pickFromGallery(entry.key),
                    onClear: () => setState(() => _shots.remove(entry.key)),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  // Enabled as soon as there is something to send: a partial
                  // submission still moves the application forward, and the
                  // reviewer asks for whatever is missing. Blocking on all four
                  // would strand an agent who genuinely has only three.
                  onPressed: (_busy || _shots.isEmpty) ? null : _submit,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_rounded),
                  label: Text(
                    _shots.isEmpty
                        ? 'Capture a document to continue'
                        : 'Submit ${_shots.length} document'
                            '${_shots.length == 1 ? '' : 's'}',
                  ),
                ),
              ] else if (kyc.isPending)
                const AppCard(
                  child: Text(
                    'Your documents are with our verification team. You\'ll be '
                    'notified as soon as a decision is made — there\'s nothing '
                    'more to do right now.',
                  ),
                ),
              if (kyc.documents.isNotEmpty) ...[
                const SizedBox(height: 20),
                const SectionHeader('Submitted'),
                const SizedBox(height: 8),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < kyc.documents.length; i++) ...[
                        ListTile(
                          leading: const Icon(Icons.description_outlined),
                          title: Text(kyc.documents[i].label),
                          trailing: StatusPill(
                            label: _statusLabel(kyc.documents[i].status),
                            color: _statusColor(kyc.documents[i].status),
                          ),
                        ),
                        if (i < kyc.documents.length - 1)
                          const Divider(height: 1),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Colour for a KYC status word. Verified reads as done, rejected as needing
/// action, everything else as in-flight.
Color _statusColor(String status) => switch (status) {
      'verified' => AgentColors.green,
      'rejected' => AgentColors.danger,
      'pending' || 'in_review' => AgentColors.amber,
      _ => AgentColors.textSecondary,
    };

String _statusLabel(String status) =>
    status.replaceAll('_', ' ').toUpperCase();

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.kyc});

  final MyKyc kyc;

  /// What the agent should understand from each state — the status word alone
  /// ("rejected") tells them nothing about what to do next.
  String get _explanation {
    if (kyc.isVerified) {
      return 'Your identity is verified. Nothing further is needed.';
    }
    if (kyc.isPending) {
      return 'Submitted and awaiting review.';
    }
    if (kyc.isRejected) {
      return kyc.rejectionReason.isNotEmpty
          ? kyc.rejectionReason
          : 'Your documents were not accepted. Please capture them again, '
              'making sure every corner is visible and the text is readable.';
    }
    return 'Verify your identity to keep taking deliveries and collections.';
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Status', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              StatusPill(
                  label: _statusLabel(kyc.status),
                  color: _statusColor(kyc.status)),
            ],
          ),
          const SizedBox(height: 8),
          Text(_explanation),
        ],
      ),
    );
  }
}

class _DocRow extends StatelessWidget {
  const _DocRow({
    required this.type,
    required this.label,
    required this.shot,
    required this.alreadyUploaded,
    required this.enabled,
    required this.onCapture,
    required this.onGallery,
    required this.onClear,
  });

  final String type;
  final String label;
  final XFile? shot;
  final bool alreadyUploaded;
  final bool enabled;
  final VoidCallback onCapture;
  final VoidCallback onGallery;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final captured = shot != null;
    return AppCard(
      child: Row(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: captured
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(File(shot!.path), fit: BoxFit.cover),
                  )
                : Icon(
                    alreadyUploaded
                        ? Icons.check_circle_outline_rounded
                        : Icons.add_a_photo_outlined,
                    size: 32,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  captured
                      ? 'Ready to submit'
                      : alreadyUploaded
                          ? 'Already on file — recapture to replace it'
                          : 'Not captured',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (captured)
            IconButton(
              tooltip: 'Remove',
              onPressed: enabled ? onClear : null,
              icon: const Icon(Icons.close_rounded),
            ),
          IconButton(
            tooltip: 'Choose from gallery',
            onPressed: enabled ? onGallery : null,
            icon: const Icon(Icons.photo_library_outlined),
          ),
          IconButton(
            tooltip: captured ? 'Retake' : 'Take photo',
            onPressed: enabled ? onCapture : null,
            icon: const Icon(Icons.camera_alt_rounded),
          ),
        ],
      ),
    );
  }
}
