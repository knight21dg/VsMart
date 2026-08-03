import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/destination_map.dart';
import '../../../core/gps.dart';
import '../../../core/ui.dart';
import '../../deliveries/presentation/deliveries_providers.dart'
    show locationServiceProvider;
import '../data/verification_data.dart';
import 'verification_providers.dart';
import 'verification_submitted_screen.dart';
import 'verification_tasks_screen.dart'
    show verificationStatusColor, verificationStatusLabel, verificationTypeLabel;

/// Drives a single field-verification task through its lifecycle:
///
///   pending/assigned → [Start Visit] (claim)
///   in_progress      → [Capture GPS] + [Capture Photo] → [Submit]
///   submitted/approved/rejected → read-only
///
/// Reads GET /verification/tasks/{id} and re-fetches after each step so the UI
/// always reflects the backend's truth.
class VerificationDetailScreen extends ConsumerStatefulWidget {
  const VerificationDetailScreen({
    super.key,
    required this.id,
    this.customerName = '',
  });

  final String id;
  final String customerName;

  @override
  ConsumerState<VerificationDetailScreen> createState() =>
      _VerificationDetailScreenState();
}

class _VerificationDetailScreenState
    extends ConsumerState<VerificationDetailScreen> {
  bool _busy = false;
  final _picker = ImagePicker();

  VerificationRepo get _repo => ref.read(verificationRepoProvider);

  // ── error surfacing ──────────────────────────────────────────────────────
  void _show(Object error) {
    if (error is VerificationApiException) {
      final next = error.nextStep;
      showToast(
        context,
        next != null && next.isNotEmpty
            ? '${error.display}\n$next'
            : error.display,
        error: true,
      );
    } else {
      showToast(context, 'Something went wrong. Please try again.',
          error: true);
    }
  }

  /// Run an action with the busy flag + refresh + error surfacing. Returns true
  /// on success.
  Future<bool> _run(Future<void> Function() action, {String? successMsg}) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return true;
      ref.invalidate(verificationTaskDetailProvider(widget.id));
      ref.invalidate(verificationTasksProvider);
      if (successMsg != null) showToast(context, successMsg);
      return true;
    } catch (e) {
      if (mounted) _show(e);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── steps ──────────────────────────────────────────────────────────────────
  Future<void> _start() =>
      _run(() => _repo.start(widget.id), successMsg: 'Visit started');

  Future<void> _captureGps() async {
    final loc = ref.read(locationServiceProvider);
    final fix = await loc.current();
    // Require a real device fix — never submit a stale / fallback location as
    // verification evidence. Prompt the agent to enable location instead.
    if (!loc.hasDeviceGps || fix == null) {
      if (!mounted) return;
      await promptEnableLocation(context);
      return;
    }
    await _run(
      () => _repo.captureGps(widget.id,
          latitude: fix.latitude, longitude: fix.longitude),
      successMsg: 'GPS captured',
    );
  }

  Future<void> _capturePhoto() async {
    // Hardened like the POD flow: catch picker failures, recover Android's
    // lost-data case, and never exit silently.
    XFile? shot;
    try {
      shot = await _picker.pickImage(
          source: ImageSource.camera, imageQuality: 70, maxWidth: 1600);
      if (shot == null) {
        final lost = await _picker.retrieveLostData();
        if (!lost.isEmpty) shot = lost.file;
      }
    } catch (e) {
      if (mounted) showToast(context, 'Camera failed: $e', error: true);
      return;
    }
    if (shot == null) {
      if (mounted) {
        showToast(context, 'No photo received from the camera — try again.',
            error: true);
      }
      return;
    }
    final XFile photo = shot;
    await _run(
      () async {
        final bytes = await photo.readAsBytes();
        await _repo.capturePhotoFile(widget.id,
            bytes: bytes, filename: 'verify_${widget.id}.jpg');
      },
      successMsg: 'Photo captured',
    );
  }

  Future<void> _submit() async {
    final result = await showDialog<_SubmitChoice>(
      context: context,
      builder: (ctx) => const _SubmitDialog(),
    );
    if (result == null) return;
    final ok = await _run(
      () => _repo.submit(widget.id,
          decision: result.decision, note: result.note),
    );
    if (ok && mounted) {
      // Closing step → verification submitted confirmation.
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => VerificationSubmittedScreen(
          customerName: widget.customerName,
          decision: result.decision,
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(verificationTaskDetailProvider(widget.id));
    final title =
        widget.customerName.isNotEmpty ? widget.customerName : 'Verification';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: async.when(
        loading: () => const Loading(),
        error: (_, __) => ErrorRetry(
          message: 'Could not load this task.',
          onRetry: () =>
              ref.invalidate(verificationTaskDetailProvider(widget.id)),
        ),
        data: (task) => _DetailBody(
          task: task,
          busy: _busy,
          onStart: _start,
          onCaptureGps: _captureGps,
          onCapturePhoto: _capturePhoto,
          onSubmit: _submit,
        ),
      ),
    );
  }
}

/// A submit decision (optional approve/reject + optional note).
class _SubmitChoice {
  const _SubmitChoice({this.decision, this.note});
  final String? decision;
  final String? note;
}

class _SubmitDialog extends StatefulWidget {
  const _SubmitDialog();
  @override
  State<_SubmitDialog> createState() => _SubmitDialogState();
}

class _SubmitDialogState extends State<_SubmitDialog> {
  // null → submit without a decision; 'approve' / 'reject' otherwise.
  String? _decision;
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Submit verification'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Decision',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AgentColors.textSecondary)),
          const SizedBox(height: 6),
          RadioListTile<String?>(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: 'approve',
            groupValue: _decision,
            onChanged: (v) => setState(() => _decision = v),
            title: const Text('Approve'),
          ),
          RadioListTile<String?>(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: 'reject',
            groupValue: _decision,
            onChanged: (v) => setState(() => _decision = v),
            title: const Text('Reject'),
          ),
          RadioListTile<String?>(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: null,
            groupValue: _decision,
            onChanged: (v) => setState(() => _decision = v),
            title: const Text('Submit for review (no decision)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _noteController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _SubmitChoice(
              decision: _decision,
              note: _noteController.text.trim().isEmpty
                  ? null
                  : _noteController.text.trim(),
            ),
          ),
          child: const Text('Submit'),
        ),
      ],
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.task,
    required this.busy,
    required this.onStart,
    required this.onCaptureGps,
    required this.onCapturePhoto,
    required this.onSubmit,
  });

  final VerificationTask task;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onCaptureGps;
  final VoidCallback onCapturePhoto;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    // The captured on-site GPS fix (proof of visit) — prefer a GPS evidence, else
    // any evidence that carries coordinates.
    VerificationEvidence? capturedFix;
    for (final e in task.evidence) {
      if (e.hasCoords && (e.isGps || capturedFix == null)) {
        capturedFix = e;
        if (e.isGps) break;
      }
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _headerCard(),
        const SizedBox(height: 12),
        _evidenceCard(),
        if (capturedFix != null) ...[
          const SizedBox(height: 12),
          DestinationMap(
            lat: capturedFix.latitude!,
            lng: capturedFix.longitude!,
            label: 'Captured location',
            height: 180,
          ),
        ],
        const SizedBox(height: 20),
        _actionArea(),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _headerCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LeadingIcon(
                  icon: Icons.verified_user_rounded,
                  color: verificationStatusColor(task.status),
                  size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  task.customerName.isNotEmpty ? task.customerName : 'Customer',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 18),
                ),
              ),
              StatusPill(
                label: verificationStatusLabel(task.status),
                color: verificationStatusColor(task.status),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AgentColors.brand.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${verificationTypeLabel(task.type)} verification',
              style: const TextStyle(
                color: AgentColors.brand,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (task.note.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              task.note,
              style: const TextStyle(color: AgentColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _evidenceCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Evidence captured',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AgentColors.textSecondary)),
              const Spacer(),
              Text('${task.evidence.length}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AgentColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 10),
          if (task.evidence.isEmpty)
            const Text(
              'No evidence captured yet.',
              style: TextStyle(color: AgentColors.textSecondary),
            )
          else
            for (var i = 0; i < task.evidence.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _EvidenceRow(evidence: task.evidence[i]),
            ],
        ],
      ),
    );
  }

  Widget _actionArea() {
    if (task.isClaimable) {
      return _primary(
        label: 'Start Visit',
        icon: Icons.play_circle_outline,
        onPressed: onStart,
      );
    }
    if (task.isInProgress) {
      final hasGps = task.evidence.any((e) => e.isGps);
      final hasPhoto = task.evidence.any((e) => e.isPhoto);
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _secondary(
                  label: hasGps ? 'GPS captured' : 'Capture GPS',
                  icon: hasGps
                      ? Icons.check_circle_outline
                      : Icons.my_location_outlined,
                  done: hasGps,
                  onPressed: onCaptureGps,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _secondary(
                  label: hasPhoto ? 'Photo captured' : 'Capture Photo',
                  icon: hasPhoto
                      ? Icons.check_circle_outline
                      : Icons.photo_camera_outlined,
                  done: hasPhoto,
                  onPressed: onCapturePhoto,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _primary(
            label: 'Submit',
            icon: Icons.send_outlined,
            onPressed: onSubmit,
          ),
        ],
      );
    }
    // Terminal states.
    return Center(
      child: Text(
        switch (task.status) {
          'approved' => 'Verification approved.',
          'rejected' => 'Verification rejected.',
          'submitted' => 'Submitted for review.',
          _ => 'No further action.',
        },
        style: const TextStyle(color: AgentColors.textSecondary),
      ),
    );
  }

  Widget _primary({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return FilledButton.icon(
      onPressed: busy ? null : onPressed,
      icon: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
          : Icon(icon),
      label: Text(label),
    );
  }

  Widget _secondary({
    required String label,
    required IconData icon,
    required bool done,
    required VoidCallback onPressed,
  }) {
    final color = done ? AgentColors.green : AgentColors.brand;
    return OutlinedButton.icon(
      onPressed: busy ? null : onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
        minimumSize: const Size.fromHeight(48),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, overflow: TextOverflow.ellipsis),
    );
  }
}

class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow({required this.evidence});
  final VerificationEvidence evidence;

  @override
  Widget build(BuildContext context) {
    final e = evidence;
    final isPhoto = e.isPhoto;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AgentColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AgentColors.border),
      ),
      child: Row(
        children: [
          Container(
            height: 44,
            width: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AgentColors.brand.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isPhoto
                  ? Icons.photo_outlined
                  : e.isGps
                      ? Icons.my_location_outlined
                      : Icons.description_outlined,
              color: AgentColors.brand,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _kindLabel(e.kind),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  _subtitle(e),
                  style: const TextStyle(
                      color: AgentColors.textSecondary, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _kindLabel(String kind) {
    switch (kind) {
      case 'photo':
        return 'Photo';
      case 'gps':
        return 'GPS location';
      case 'document':
        return 'Document';
      default:
        return kind.isEmpty ? 'Evidence' : kind;
    }
  }

  String _subtitle(VerificationEvidence e) {
    if (e.hasCoords) {
      return '${e.latitude!.toStringAsFixed(5)}, '
          '${e.longitude!.toStringAsFixed(5)}';
    }
    if (e.photoKey.isNotEmpty) return e.photoKey;
    return e.createdAt.isNotEmpty ? e.createdAt : '—';
  }
}
