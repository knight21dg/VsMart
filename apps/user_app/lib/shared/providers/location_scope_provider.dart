import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/address/presentation/providers/address_selection_provider.dart';
import '../../features/location/presentation/providers/location_providers.dart';
import '../../features/serviceability/presentation/providers/serviceability_providers.dart';

/// The customer's delivery LOCATION, in the one priority order the whole app
/// should use.
///
/// A change-location pin-drop must win over a saved address, which must win over
/// the live device fix — otherwise a customer who explicitly picks a location
/// keeps being served their old area. The catalog had this chain; offers only
/// read the saved address, so a GPS-only session (new user, guest, or anyone who
/// hasn't saved an address) sent NO location at all and got global banners and
/// deals — for other cities, on products their store doesn't carry.
class LocationScope {
  const LocationScope({this.lat, this.lng, this.pincode, this.storeId});

  final double? lat;
  final double? lng;
  final String? pincode;

  /// Server-resolved serving store, when serviceability has settled. Sent only
  /// as a transitional fallback — the backend prefers the coordinates and never
  /// lets a client-supplied store widen what is returned.
  final String? storeId;

  /// A stable key identifying the SERVING STORE for cache namespacing.
  ///
  /// Prefers the resolved store id (the thing that actually determines what is
  /// sold). Falls back to pincode, then to COARSE coordinates — 2 decimal places,
  /// roughly a kilometre — because raw GPS jitter would otherwise mint a new
  /// namespace on every tick and defeat caching entirely.
  String get cacheKey {
    if (storeId != null && storeId!.isNotEmpty) return 'store:$storeId';
    if (pincode != null && pincode!.isNotEmpty) return 'pin:$pincode';
    if (lat != null && lng != null) {
      return 'geo:${lat!.toStringAsFixed(2)},${lng!.toStringAsFixed(2)}';
    }
    return 'global';
  }
}

final locationScopeProvider = Provider<LocationScope>((ref) {
  final manual = ref.watch(manualLocationProvider);
  final address = ref.watch(selectedAddressProvider);
  final live = ref.watch(resolvedLocationProvider);
  final svc = ref.watch(currentServiceabilityProvider);

  return LocationScope(
    lat: manual?.latitude ?? address?.latitude ?? live?.latitude,
    lng: manual?.longitude ?? address?.longitude ?? live?.longitude,
    pincode: manual?.pincode ?? address?.pincode ?? live?.pincode,
    storeId: svc.serviceable ? svc.storeId : null,
  );
});
