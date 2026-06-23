import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/serviceability_result.dart';
import 'serviceability_providers.dart';

/// The hard-lock verdict for the whole app, distinct from the raw
/// [ServiceabilityResult] (whose `.unknown` value reports `serviceable == false`
/// and must NOT be treated as a positively-resolved "out of coverage").
enum GateStatus {
  /// No GPS-based check has resolved yet (first launch / still loading). The
  /// router shows a brief "Checking your area…" state — it must NOT hard-lock.
  unresolved,

  /// A GPS check is actively in flight with no prior verdict.
  checking,

  /// Positively resolved INSIDE a serving zone → full app access.
  serviceable,

  /// Positively resolved OUTSIDE every zone → hard-lock ("not in your area").
  unserviceable,

  /// GPS permission/service denied or unavailable, OR the check could not be
  /// completed. Coverage can't be confirmed, so we fail CLOSED and lock in a
  /// "set your location" mode — but always allow a retry.
  locationUnavailable,
}

extension GateStatusX on GateStatus {
  /// Whether this verdict should hard-lock the app behind the lock screen.
  bool get isLocked =>
      this == GateStatus.unserviceable || this == GateStatus.locationUnavailable;

  /// Whether we're still resolving the very first verdict (show a loader, don't
  /// lock yet).
  bool get isResolving =>
      this == GateStatus.unresolved || this == GateStatus.checking;
}

/// Session-scoped serviceability HARD LOCK.
///
/// Owns the GPS-based "can this user use the app at all?" decision. It runs the
/// device-location serviceability check once per session ([ensureChecked]) and
/// exposes a [GateStatus] the router redirect gates every main route on.
///
/// Crucially it distinguishes a POSITIVELY-resolved unserviceable result (a real
/// [ServiceabilityResult] with `serviceable == false` that is NOT the sentinel
/// [ServiceabilityResult.unknown]) from a merely-unresolved/loading state, so a
/// transient error or a still-loading check can never wrongly brick the app.
class ServiceabilityGateController extends Notifier<GateStatus> {
  bool _started = false;

  @override
  GateStatus build() => GateStatus.unresolved;

  /// Runs the GPS-based serviceability resolve once per session. Re-entrant
  /// calls are ignored unless [force] is set (used by the lock screen retry).
  Future<void> ensureChecked({bool force = false}) async {
    if (_started && !force) return;
    _started = true;
    await _runDetect();
  }

  /// Re-detect the device location and re-evaluate (lock-screen "use my
  /// location" path).
  Future<GateStatus> recheck() async {
    await _runDetect();
    return state;
  }

  /// Resolve serviceability for an explicit coordinate / pincode entered on the
  /// lock screen, then update the gate. Returns the new status so the caller can
  /// react (unlock vs. "still not covered").
  Future<GateStatus> recheckCoordinate({
    double? latitude,
    double? longitude,
    String? pincode,
  }) async {
    _started = true;
    if (state.isResolving || !state.isLocked) {
      state = GateStatus.checking;
    }
    try {
      final result =
          await ref.read(serviceabilityProvider.notifier).checkCoordinate(
                latitude: latitude,
                longitude: longitude,
                pincode: pincode,
              );
      state = _verdictFor(result);
    } catch (_) {
      // Couldn't confirm coverage → fail closed, but keep retry open.
      state = GateStatus.locationUnavailable;
    }
    return state;
  }

  Future<void> _runDetect() async {
    // Only flash the loader when we don't already have a hard verdict to keep
    // showing (avoids a serviceable→checking→serviceable flicker on retry).
    if (state.isResolving) state = GateStatus.checking;
    try {
      final result =
          await ref.read(serviceabilityProvider.notifier).detectAndResolve();
      if (result == null) {
        // GPS permission/service denied or no fix — fail closed.
        state = GateStatus.locationUnavailable;
        return;
      }
      state = _verdictFor(result);
    } catch (_) {
      state = GateStatus.locationUnavailable;
    }
  }

  /// Maps a [ServiceabilityResult] returned by a COMPLETED check to a verdict.
  ///
  /// This is only ever called with the result of a successful network check
  /// ([ServiceabilityController.detectAndResolve] / [checkCoordinate]), never
  /// with the cached/`.unknown` sentinel — so a `serviceable == false` here is a
  /// POSITIVELY-resolved out-of-coverage answer from the backend (whose
  /// not-serviceable payload is all-null, equal to the sentinel by value but
  /// distinct in meaning). "Couldn't confirm" cases — no GPS fix, or a thrown
  /// request — are handled by the callers as [GateStatus.locationUnavailable]
  /// and never reach here.
  GateStatus _verdictFor(ServiceabilityResult result) =>
      result.serviceable ? GateStatus.serviceable : GateStatus.unserviceable;
}

final serviceabilityGateProvider =
    NotifierProvider<ServiceabilityGateController, GateStatus>(
  ServiceabilityGateController.new,
);
