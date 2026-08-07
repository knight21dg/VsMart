import '../../../../app/constants/storage_keys.dart';
import '../../../../core/storage/hive_service.dart';
import '../../domain/entities/address.dart';
import '../../domain/repositories/address_repository.dart';
import '../datasources/address_remote_datasource.dart';
import '../models/address_model.dart';

/// [AddressRepository] backed by the backend (`/api/v1/addresses`) with a Hive
/// **cache mirror**: the server is authoritative, every mutation syncs to it and
/// then refreshes the cache, while synchronous reads serve the cache (so the UI
/// stays snappy/offline-tolerant and no layer needs to become async).
class AddressRepositoryImpl implements AddressRepository {
  AddressRepositoryImpl(this._hive, this._remote);

  final HiveService _hive;
  final AddressRemoteDataSource _remote;

  List<Address> _readCache() {
    final raw = _hive.addressBox.get(StorageKeys.addresses);
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => AddressModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return [];
  }

  Future<List<Address>> _writeCache(List<Address> items) async {
    final sorted = [...items]
      ..sort((a, b) => (b.isDefault ? 1 : 0) - (a.isDefault ? 1 : 0));
    await _hive.addressBox
        .put(StorageKeys.addresses, sorted.map(AddressModel.toJson).toList());
    return List.unmodifiable(sorted);
  }

  @override
  List<Address> getAll() => List.unmodifiable(_readCache());

  @override
  Address? getDefault() {
    final items = _readCache();
    if (items.isEmpty) return null;
    return items.firstWhere((a) => a.isDefault, orElse: () => items.first);
  }

  @override
  Future<List<Address>> refresh() async {
    try {
      return _writeCache(await _remote.list());
    } catch (_) {
      // Offline / transient error → keep serving the cache.
      return List.unmodifiable(_readCache());
    }
  }

  @override
  Future<List<Address>> add(Address address, {bool makeDefault = false}) async {
    final shouldDefault = makeDefault || _readCache().isEmpty;
    await _remote.create(address.copyWith(isDefault: shouldDefault));
    return refresh();
  }

  @override
  Future<List<Address>> update(Address address) async {
    await _remote.update(address);
    return refresh();
  }

  @override
  Future<List<Address>> remove(String id) async {
    await _remote.delete(id);
    return refresh();
  }

  @override
  Future<List<Address>> setDefault(String id) async {
    await _remote.setDefault(id);
    return refresh();
  }
}
