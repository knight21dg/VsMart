import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/collections/collections_providers.dart';
import '../../features/deliveries/presentation/deliveries_providers.dart';
import '../../features/returns/returns_providers.dart';
import '../../features/verification/presentation/verification_providers.dart';

/// Keeps the agent's work queues live.
///
/// Every queue is a `FutureProvider.autoDispose`, but [HomeShell] renders all
/// five tabs inside an `IndexedStack`, so each screen stays mounted for the
/// whole session. Nothing ever disposed those providers, so their futures
/// resolved exactly once at launch and the cached list was served forever: a
/// collection, delivery or return pickup assigned *after* the agent opened the
/// app was invisible until they manually pulled to refresh or restarted it.
///
/// Push was supposed to prompt a refresh, but the push handler only invalidated
/// the notification inbox — and FCM is credential-gated, so on an install
/// without Firebase credentials no assignment ever rings at all.
///
/// So this polls on a timer while the app is foregrounded, and refreshes
/// immediately on resume. [refreshNow] is also called by the push handler so a
/// delivered push updates the queues instantly rather than waiting for the next
/// tick.
class TaskSync with WidgetsBindingObserver {
  TaskSync(this._ref);

  final Ref _ref;
  Timer? _timer;

  /// Frequent enough that a new task feels immediate, cheap enough to leave
  /// running: these are small, agent-scoped list endpoints.
  static const pollInterval = Duration(seconds: 30);

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _schedule();
    refreshNow();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer.periodic(pollInterval, (_) => refreshNow());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _schedule();
      refreshNow();
    } else {
      // Don't poll in the background — the OS would throttle it anyway and it
      // only burns the agent's battery and data.
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Re-fetch every work queue. Invalidating a provider nobody is watching
  /// throws, so each one is guarded individually — one dead provider must not
  /// stop the others from refreshing.
  void refreshNow() {
    for (final provider in <ProviderOrFamily>[
      assignedCollectionsProvider,
      assignedDeliveriesProvider,
      assignedReturnPickupsProvider,
      verificationTasksProvider,
      currentBatchProvider,
    ]) {
      try {
        _ref.invalidate(provider);
      } catch (_) {
        // Not currently alive — it will load fresh when something watches it.
      }
    }
  }
}

final taskSyncProvider = Provider<TaskSync>((ref) {
  final sync = TaskSync(ref);
  ref.onDispose(sync.dispose);
  return sync;
});
