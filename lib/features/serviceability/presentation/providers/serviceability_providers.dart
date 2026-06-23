import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/core_providers.dart';
import '../../../address/presentation/providers/address_selection_provider.dart';
import '../../data/serviceability_data_source.dart';
import '../../data/serviceability_result.dart';

const _cacheKey = 'serviceability:last';

final serviceabilityDataSourceProvider = Provider<ServiceabilityDataSource>(
  (ref) => ServiceabilityDataSource(ref.watch(apiClientProvider)),
);

/// Resolves and caches serviceability for the customer's current location.
///
/// Auto-resolves from the selected delivery address (the "address" validation
/// moment) and mirrors the last result into the Hive cache so the rest of the
/// app can read it synchronously and offline. GPS-based resolution is available
/// via [checkCoordinate] / [detectAndResolve] for an explicit "use my location".
class ServiceabilityController extends AsyncNotifier<ServiceabilityResult> {
  @override
  Future<ServiceabilityResult> build() async {
    final cached = _readCache();
    final address = ref.watch(selectedAddressProvider);
    if (address == null) {
      return cached ?? ServiceabilityResult.unknown;
    }
    try {
      final result = await ref.read(serviceabilityDataSourceProvider).check(
            latitude: address.latitude,
            longitude: address.longitude,
            pincode: address.pincode,
          );
      _writeCache(result);
      return result;
    } catch (_) {
      // Fail soft: keep showing the last known serviceability rather than
      // bricking the app on a flaky check.
      return cached ?? ServiceabilityResult.unknown;
    }
  }

  /// Resolve serviceability for an explicit coordinate / pincode.
  Future<ServiceabilityResult> checkCoordinate({
    double? latitude,
    double? longitude,
    String? pincode,
  }) async {
    state = const AsyncLoading<ServiceabilityResult>().copyWithPrevious(state);
    try {
      final result = await ref.read(serviceabilityDataSourceProvider).check(
            latitude: latitude,
            longitude: longitude,
            pincode: pincode,
          );
      _writeCache(result);
      state = AsyncData(result);
      return result;
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }

  /// Detect the device location via GPS, then resolve serviceability for it.
  /// Returns null if location permission/service is unavailable.
  Future<ServiceabilityResult?> detectAndResolve() async {
    final pos = await ref.read(locationServiceProvider).getCurrentPosition();
    if (pos == null) return null;
    return checkCoordinate(latitude: pos.latitude, longitude: pos.longitude);
  }

  ServiceabilityResult? _readCache() {
    try {
      final raw = ref.read(hiveServiceProvider).cacheBox.get(_cacheKey);
      if (raw is String && raw.isNotEmpty) {
        return ServiceabilityResult.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
      }
    } catch (_) {/* ignore corrupt cache */}
    return null;
  }

  void _writeCache(ServiceabilityResult result) {
    try {
      ref
          .read(hiveServiceProvider)
          .cacheBox
          .put(_cacheKey, jsonEncode(result.toJson()));
    } catch (_) {/* best-effort cache */}
  }
}

final serviceabilityProvider =
    AsyncNotifierProvider<ServiceabilityController, ServiceabilityResult>(
        ServiceabilityController.new);

/// Synchronous best-known serviceability — the live value if resolved, else the
/// last cached one, else [ServiceabilityResult.unknown]. Use for banners/gates
/// that can't await.
final currentServiceabilityProvider = Provider<ServiceabilityResult>((ref) {
  return ref.watch(serviceabilityProvider).valueOrNull ??
      ServiceabilityResult.unknown;
});
