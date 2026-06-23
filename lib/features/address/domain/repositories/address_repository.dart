import '../entities/address.dart';

/// Local persistence for the customer's saved delivery addresses (multi-address
/// with a single default). Reads are synchronous; mutations return the updated
/// list. A remote sync layer can be added behind this interface later.
abstract interface class AddressRepository {
  /// All saved addresses (default first) — served synchronously from the local
  /// cache mirror of the server state.
  List<Address> getAll();

  /// Re-fetch from the backend and refresh the local cache (call on login/open).
  Future<List<Address>> refresh();

  /// The default address, or the first available, or null when empty.
  Address? getDefault();

  /// Add [address]; when [makeDefault] is true (or it is the first address) it
  /// becomes the default.
  Future<List<Address>> add(Address address, {bool makeDefault = false});

  /// Update an existing address by id.
  Future<List<Address>> update(Address address);

  /// Remove an address by id (promotes another to default if needed).
  Future<List<Address>> remove(String id);

  /// Mark the address with [id] as the default.
  Future<List<Address>> setDefault(String id);
}
