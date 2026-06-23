import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/location_service.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../data/datasources/address_remote_datasource.dart';
import '../../data/repositories/address_repository_impl.dart';
import '../../domain/entities/address.dart';
import '../../domain/repositories/address_repository.dart';

final addressRepositoryProvider = Provider<AddressRepository>(
  (ref) => AddressRepositoryImpl(
    ref.watch(hiveServiceProvider),
    AddressRemoteDataSource(ref.watch(apiClientProvider)),
  ),
);

/// Holds the saved address list, loading from storage and persisting mutations
/// through the repository.
class AddressController extends Notifier<List<Address>> {
  AddressRepository get _repo => ref.read(addressRepositoryProvider);
  LocationService get _location => ref.read(locationServiceProvider);

  @override
  List<Address> build() {
    _hydrate(); // refresh from the backend; cache serves the first frame
    return _repo.getAll();
  }

  Future<void> _hydrate() async {
    final items = await _repo.refresh();
    try {
      state = items;
    } catch (_) {/* controller disposed mid-flight — ignore */}
  }

  Future<void> add(Address address, {bool makeDefault = false}) async =>
      state = await _repo.add(address, makeDefault: makeDefault);

  Future<void> update(Address address) async =>
      state = await _repo.update(address);

  Future<void> remove(String id) async => state = await _repo.remove(id);

  Future<void> setDefault(String id) async =>
      state = await _repo.setDefault(id);

  /// Detects the device location and saves it as the default address. Returns
  /// true if a position was captured, false if permission/service was denied.
  Future<bool> detectAndSetLocation() async {
    final position = await _location.getCurrentPosition();
    if (position == null) return false;

    final detected = Address(
      id: 'auto-detected-${DateTime.now().millisecondsSinceEpoch}',
      name: 'Current Location',
      phone: '',
      line1: 'Lat ${position.latitude.toStringAsFixed(4)}, '
          'Lng ${position.longitude.toStringAsFixed(4)}',
      area: 'Current Location',
      district: '',
      state: '',
      pincode: '',
      latitude: position.latitude,
      longitude: position.longitude,
      isDefault: state.isEmpty,
    );

    await add(detected, makeDefault: true);
    return true;
  }
}

final addressesProvider =
    NotifierProvider<AddressController, List<Address>>(AddressController.new);

/// The current default address (or first available).
final defaultAddressProvider = Provider<Address?>((ref) {
  final items = ref.watch(addressesProvider);
  if (items.isEmpty) return null;
  for (final a in items) {
    if (a.isDefault) return a;
  }
  return items.first;
});
