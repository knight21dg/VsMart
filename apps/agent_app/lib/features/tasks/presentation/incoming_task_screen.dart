import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  bool _busy = false;
  final _local = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    // The notification behind this screen is the thing actually "ringing"
    // (its sound repeats on its own via FLAG_INSISTENT) — this is just the
    // in-app echo of that so it's felt even with the phone silenced/on
    // vibrate, where the notification's own sound wouldn't be heard anyway.
    _pulse = Timer.periodic(
        const Duration(milliseconds: 1200), (_) => HapticFeedback.heavyImpact());
  }

  @override
  void dispose() {
    _pulse?.cancel();
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
      if (mounted) {
        setState(() => _busy = false);
        showApiError(context, e,
            fallback:
                "Couldn't ${accept ? 'accept' : 'reject'} — try again.");
      }
    }
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
