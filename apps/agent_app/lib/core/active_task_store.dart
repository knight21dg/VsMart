import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The delivery task id the agent is currently `out_for_delivery` on, if any —
/// the one piece of state [background_service.dart]'s presence-ping isolate
/// needs but can't get any other way.
///
/// That isolate runs independently of the main app (it has to: a plain Dart
/// Timer dies the instant Android kills the app process, which is exactly
/// when this matters most) and can't reach Riverpod providers or any other
/// in-memory app state. Secure storage is the one thing both isolates can
/// read, and — critically — it survives the main app process being killed,
/// which an in-memory value would not.
///
/// Without this, the background service's presence ping is permanently
/// task-less by design (see its own docstring), so a delivery in progress
/// whose app gets backgrounded/killed stops updating the customer's live
/// tracking map the moment the foreground 15s breadcrumb timer dies with it
/// — the marker just freezes, with nothing telling anyone why.
class ActiveTaskStore {
  ActiveTaskStore([this._s = const FlutterSecureStorage()]);

  final FlutterSecureStorage _s;

  static const _key = 'agent_active_out_for_delivery_task_id';

  Future<void> set(String? taskId) async {
    if (taskId == null || taskId.isEmpty) {
      await _s.delete(key: _key);
    } else {
      await _s.write(key: _key, value: taskId);
    }
  }

  Future<String?> get current => _s.read(key: _key);
}
