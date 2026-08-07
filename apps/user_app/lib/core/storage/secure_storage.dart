import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thin wrapper around [FlutterSecureStorage] for encrypted key-value storage.
class SecureStorage {
  SecureStorage(this._storage);

  final FlutterSecureStorage _storage;

  static const AndroidOptions _androidOptions =
      AndroidOptions(encryptedSharedPreferences: true);

  factory SecureStorage.create() =>
      SecureStorage(const FlutterSecureStorage(aOptions: _androidOptions));

  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  Future<String?> read(String key) => _storage.read(key: key);

  Future<void> delete(String key) => _storage.delete(key: key);

  Future<void> deleteAll() => _storage.deleteAll();

  Future<bool> contains(String key) => _storage.containsKey(key: key);
}
