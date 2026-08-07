import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/core_providers.dart';
import '../../../address/presentation/providers/address_selection_provider.dart';
import '../../data/geocoding_service.dart';
import '../../data/places_service.dart';
import '../../domain/entities/resolved_location.dart';

/// Hive key for the last resolved device location (persists across restarts so the
/// delivery header shows the last-known area instantly on open).
const _lastLocationKey = 'location:last';

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
    this.manual = false,
  });

  final LocationStatus status;
  final ResolvedLocation? location;

  /// True when [location] was chosen EXPLICITLY by the customer via the
  /// change-location pin-drop / place-search (banner or lock screen), as opposed
  /// to being resolved from GPS. A manual pick takes priority over the selected
  /// saved address for catalog + serviceability (see [manualLocationProvider]) so
  /// the change-location loop actually closes, and it is cleared the moment the
  /// customer deliberately switches saved address or a fresh GPS pass resolves.
  final bool manual;

  bool get isLoading => status == LocationStatus.loading;
  bool get isResolved =>
      status == LocationStatus.resolved && location != null;
  bool get isPermissionDenied => status == LocationStatus.permissionDenied;

  DeviceLocationState copyWith({
    LocationStatus? status,
    ResolvedLocation? location,
    bool? manual,
  }) {
    return DeviceLocationState(
      status: status ?? this.status,
      location: location ?? this.location,
      manual: manual ?? this.manual,
    );
  }
}

final geocodingServiceProvider = Provider<GeocodingService>(
  (ref) => GeocodingService(ref.watch(apiClientProvider)),
);

final placesServiceProvider = Provider<PlacesService>(
  (ref) => PlacesService(ref.watch(apiClientProvider)),
);

/// Resolves and caches the device's current delivery location for the session.
///
/// Call [ensureResolved] once on home open; it acquires permission + GPS, then
/// reverse-geocodes (backend first, native fallback). The result persists in
/// this provider so other screens (e.g. the address header) reuse it without
/// re-prompting. [refresh] forces a fresh lookup (e.g. on a manual retry).
class LocationController extends Notifier<DeviceLocationState> {
  @override
  DeviceLocationState build() {
    // A deliberate saved-address switch supersedes any manual change-location
    // pick, so the address book stays the source of truth whenever the customer
    // actually uses it. (Fires only on later changes, never the initial default.)
    ref.listen(addressSelectionProvider, (prev, next) {
      if (prev?.selectedId != next.selectedId && state.manual) {
        _set(state.copyWith(manual: false));
      }
    });
    // Open with the LAST-KNOWN location so the delivery header shows the area
    // instantly instead of "detecting…". A fresh GPS pass still runs on Home
    // (ensureResolved) and updates this in the background.
    final cached = _readCache();
    if (cached != null) {
      return DeviceLocationState(
          status: LocationStatus.resolved, location: cached);
    }
    return const DeviceLocationState();
  }

  ResolvedLocation? _readCache() {
    try {
      final raw = ref.read(hiveServiceProvider).cacheBox.get(_lastLocationKey);
      if (raw is String && raw.isNotEmpty) {
        return ResolvedLocation.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
      }
    } catch (_) {/* ignore corrupt cache */}
    return null;
  }

  void _writeCache(ResolvedLocation loc) {
    try {
      ref
          .read(hiveServiceProvider)
          .cacheBox
          .put(_lastLocationKey, jsonEncode(loc.toJson()));
    } catch (_) {/* best-effort */}
  }

  /// True once a FRESH GPS pass has completed this session (a hydrated cache value
  /// doesn't count — it must be refreshed once on Home).
  bool _resolvedThisSession = false;

  /// Resolves the location once per session. A cached/last-known value shown at
  /// startup does NOT satisfy this — Home still triggers one fresh pass so the
  /// serviceability check runs against the real current location.
  Future<void> ensureResolved({bool force = false}) async {
    if (!force &&
        (state.status == LocationStatus.loading || _resolvedThisSession)) {
      return;
    }
    await _resolve();
  }

  /// Forces a fresh GPS + reverse-geocode pass.
  Future<void> refresh() => _resolve();

  /// Persists a delivery location the customer PICKED explicitly (change-location
  /// pin-drop / place-search on the banner or lock screen). Marks it [manual] so
  /// it takes priority over the selected saved address for catalog + serviceability
  /// (closing the change-location loop), and flags the session as resolved so the
  /// background GPS pass on Home won't clobber the customer's deliberate choice.
  void applyPickedLocation(ResolvedLocation location) {
    _resolvedThisSession = true;
    _writeCache(location); // becomes the next launch's last-known location too
    _set(DeviceLocationState(
      status: LocationStatus.resolved,
      location: location,
      manual: true,
    ));
  }

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
      _resolvedThisSession = true;
      _writeCache(resolved); // persist as the next launch's last-known location
      _set(DeviceLocationState(
        status: LocationStatus.resolved,
        location: resolved,
      ));
    } catch (_) {
      final fallback = ResolvedLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        source: 'none',
      );
      _resolvedThisSession = true;
      _writeCache(fallback);
      _set(DeviceLocationState(
        status: LocationStatus.resolved,
        location: fallback,
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

/// The location the customer PICKED explicitly via change-location, or null when
/// the active location is the GPS/last-known one. When non-null it takes priority
/// over the selected saved address for catalog + serviceability resolution, so a
/// change-location pin-drop actually re-binds the catalog store and verdict to the
/// new spot instead of reverting on the next rebuild.
final manualLocationProvider = Provider<ResolvedLocation?>((ref) {
  final state = ref.watch(locationControllerProvider);
  return state.manual ? state.location : null;
});
