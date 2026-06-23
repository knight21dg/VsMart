import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/core_providers.dart';
import '../../data/geocoding_service.dart';
import '../../domain/entities/resolved_location.dart';

/// Lifecycle of the device-location resolution shown in the delivery header.
enum LocationStatus {
  /// Not yet attempted.
  idle,

  /// Acquiring GPS / reverse-geocoding.
  loading,

  /// Resolved successfully ([DeviceLocationState.location] is non-null).
  resolved,

  /// Location permission (or the location service) was denied.
  permissionDenied,

  /// GPS or reverse geocoding failed for another reason.
  error,
}

/// Immutable state for the device-location feature.
class DeviceLocationState {
  const DeviceLocationState({
    this.status = LocationStatus.idle,
    this.location,
  });

  final LocationStatus status;
  final ResolvedLocation? location;

  bool get isLoading => status == LocationStatus.loading;
  bool get isResolved =>
      status == LocationStatus.resolved && location != null;
  bool get isPermissionDenied => status == LocationStatus.permissionDenied;

  DeviceLocationState copyWith({
    LocationStatus? status,
    ResolvedLocation? location,
  }) {
    return DeviceLocationState(
      status: status ?? this.status,
      location: location ?? this.location,
    );
  }
}

final geocodingServiceProvider = Provider<GeocodingService>(
  (ref) => GeocodingService(ref.watch(apiClientProvider)),
);

/// Resolves and caches the device's current delivery location for the session.
///
/// Call [ensureResolved] once on home open; it acquires permission + GPS, then
/// reverse-geocodes (backend first, native fallback). The result persists in
/// this provider so other screens (e.g. the address header) reuse it without
/// re-prompting. [refresh] forces a fresh lookup (e.g. on a manual retry).
class LocationController extends Notifier<DeviceLocationState> {
  @override
  DeviceLocationState build() => const DeviceLocationState();

  /// Resolves the location once. No-op if already resolving or resolved unless
  /// [force] is set.
  Future<void> ensureResolved({bool force = false}) async {
    if (!force &&
        (state.status == LocationStatus.loading || state.isResolved)) {
      return;
    }
    await _resolve();
  }

  /// Forces a fresh GPS + reverse-geocode pass.
  Future<void> refresh() => _resolve();

  Future<void> _resolve() async {
    state = state.copyWith(status: LocationStatus.loading);
    final locationService = ref.read(locationServiceProvider);

    final granted = await locationService.ensurePermission();
    if (!granted) {
      _set(const DeviceLocationState(status: LocationStatus.permissionDenied));
      return;
    }

    final position = await locationService.getCurrentPosition();
    if (position == null) {
      _set(const DeviceLocationState(status: LocationStatus.error));
      return;
    }

    try {
      final resolved = await ref
          .read(geocodingServiceProvider)
          .reverse(position.latitude, position.longitude);
      _set(DeviceLocationState(
        status: LocationStatus.resolved,
        location: resolved,
      ));
    } catch (_) {
      _set(DeviceLocationState(
        status: LocationStatus.resolved,
        location: ResolvedLocation(
          latitude: position.latitude,
          longitude: position.longitude,
          source: 'none',
        ),
      ));
    }
  }

  /// Guards against assigning state after the notifier is disposed mid-flight.
  void _set(DeviceLocationState next) {
    try {
      state = next;
    } catch (_) {/* disposed — ignore */}
  }
}

final locationControllerProvider =
    NotifierProvider<LocationController, DeviceLocationState>(
  LocationController.new,
);

/// The current resolved location, or null until one is available.
final resolvedLocationProvider = Provider<ResolvedLocation?>(
  (ref) => ref.watch(locationControllerProvider).location,
);
