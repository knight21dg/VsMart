import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api_exception.dart';
import '../../../core/services/push_routing.dart';
import '../../../core/ui.dart';
import '../../collections/collections_providers.dart';
import '../../deliveries/presentation/deliveries_providers.dart';

/// The full-screen "incoming call" style alert for a brand-new delivery or
/// collection assignment — pushed on top of whatever the agent was doing
/// (foreground), auto-launched over the lock screen (background/terminated,
/// via the notification's `fullScreenIntent`), or opened from a tap on the
/// alert notification itself.
///
/// It keeps ringing (the notification behind it repeats its sound + vibration
/// via `FLAG_INSISTENT`, see push_routing.dart) until the agent actually
/// answers — Accept or Reject, both real API calls, not just "close this
/// screen". There's no neutral "look later" escape: a task worth ringing for
/// is worth a real decision, same as an actual phone call.
class IncomingTaskScreen extends ConsumerStatefulWidget {
  const IncomingTaskScreen({super.key, required this.data});

  final Map<String, dynamic> data;

  @override
  ConsumerState<IncomingTaskScreen> createState() =>
      _IncomingTaskScreenState();
}

class _IncomingTaskScreenState extends ConsumerState<IncomingTaskScreen> {
  Timer? _pulse;
  Timer? _pulseStop;
  bool _busy = false;
  final _local = FlutterLocalNotificationsPlugin();

  /// How long the in-app haptic keeps pulsing. The screen is already open and
  /// impossible to miss; buzzing indefinitely while the agent reads the address
  /// is just noise, and it kept going for as long as they took to decide.
  static const _pulseLimit = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    // Silence the RINGING NOTIFICATION the moment this screen is up. It exists
    // to summon the agent; once they're looking at it, its job is done. It was
    // only cancelled in `dispose()`, so FLAG_INSISTENT kept re-sounding the
    // alert underneath the very screen the agent was reading — the "alert
    // won't turn off" complaint. The haptic below remains as the in-app cue.
    cancelRingingAlert(_local, widget.data);

    // In-app echo of the ring, so urgency is felt even on a silenced phone —
    // but bounded, unlike before.
    _pulse = Timer.periodic(
        const Duration(milliseconds: 1200), (_) => HapticFeedback.heavyImpact());
    _pulseStop = Timer(_pulseLimit, () {
      _pulse?.cancel();
      _pulse = null;
    });
  }

  @override
  void dispose() {
    _pulse?.cancel();
    _pulseStop?.cancel();
    // Leaving this screen by any path (answered, or backed out of) silences
    // the ring — an agent who backs out can still act on the task normally
    // from their task list; it just stops interrupting them.
    cancelRingingAlert(_local, widget.data);
    super.dispose();
  }

  bool get _isDelivery =>
      (widget.data['kind'] ?? '').toString().contains('delivery');

  String get _deliveryId => (widget.data['taskId'] ?? '').toString();
  String get _collectionId => (widget.data['collectionId'] ?? '').toString();

  Future<void> _respond({required bool accept}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_isDelivery) {
        final repo = ref.read(deliveriesRepoProvider);
        if (accept) {
          await repo.accept(_deliveryId);
        } else {
          await repo.reject(_deliveryId, '');
        }
      } else {
        final repo = ref.read(collectionsRepoProvider);
        if (accept) {
          await repo.accept(_collectionId);
        } else {
          await repo.reject(_collectionId, '');
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      if (accept) {
        final detail = detailScreenForPush(widget.data);
        if (detail != null) {
          Navigator.of(context)
              .push(MaterialPageRoute<void>(builder: (_) => detail));
        }
      }
    } catch (e) {
      if (!mounted) return;
      // The offer is gone — reassigned by the dispatch engine, or already
      // actioned. That is not something the rider can retry: the old code
      // showed "Couldn't reject — try again" and left them tapping a button
      // that could never succeed, which is what made Reject look broken.
      // (A 404 means the same thing: the task endpoint is scoped to the
      // signed-in agent, so it stops matching the moment it moves away.)
      if (_isDeadOffer(e)) {
        showToast(context, accept
            ? 'That job went to another partner.'
            : 'That job already moved on — nothing to reject.');
        Navigator.of(context).pop();
        return;
      }
      setState(() => _busy = false);
      showApiError(context, e,
          fallback: "Couldn't ${accept ? 'accept' : 'reject'} — try again.");
    }
  }

  /// Whether the failure means "this task is no longer yours", in which case
  /// dismissing the alert is the correct outcome rather than an error.
  bool _isDeadOffer(Object e) {
    if (e is! ApiException) return false;
    return e.code == 'DELIVERY_TASK_REQUIRED' ||
        e.code == 'COLLECTION_TASK_REQUIRED' ||
        e.code == 'INVALID_DELIVERY_TRANSITION' ||
        e.code == 'INVALID_COLLECTION_TRANSITION' ||
        e.statusCode == 404;
  }

  @override
  Widget build(BuildContext context) {
    final title =
        _isDelivery ? 'New delivery assigned' : 'New collection assigned';
    final body = (widget.data['body'] ?? '').toString();

    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: AgentColors.brandDark,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Column(
              children: [
                const Spacer(),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.85, end: 1),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.elasticOut,
                  builder: (context, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: Container(
                    width: 104,
                    height: 104,
                    decoration: const BoxDecoration(
                      color: Colors.white24,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isDelivery
                          ? Icons.local_shipping_rounded
                          : Icons.payments_rounded,
                      color: Colors.white,
                      size: 46,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                ],
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: OutlinedButton(
                          onPressed: _busy ? null : () => _respond(accept: false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54, width: 1.5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28)),
                          ),
                          child: const Text('Reject',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 16)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: FilledButton(
                          onPressed: _busy ? null : () => _respond(accept: true),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AgentColors.brandDark,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28)),
                          ),
                          child: _busy
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: AgentColors.brandDark),
                                )
                              : const Text('Accept',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700, fontSize: 16)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
