import '../../app/constants/storage_keys.dart';
import 'hive_service.dart';

/// Caches the current user's serialized profile and login flag locally so the
/// app can render an authenticated shell before the network confirms the session.
class LocalUserStorage {
  LocalUserStorage(this._hive);

  final HiveService _hive;

  Future<void> saveUser(Map<String, dynamic> userJson) async {
    await _hive.userBox.put(StorageKeys.currentUser, userJson);
    await _hive.userBox.put(StorageKeys.isLoggedIn, true);
  }

  Map<String, dynamic>? getUser() {
    final raw = _hive.userBox.get(StorageKeys.currentUser);
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  bool get isLoggedIn =>
      _hive.userBox.get(StorageKeys.isLoggedIn, defaultValue: false) as bool;

  Future<void> clear() async {
    await _hive.userBox.delete(StorageKeys.currentUser);
    await _hive.userBox.put(StorageKeys.isLoggedIn, false);
  }
}
