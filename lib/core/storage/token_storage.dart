import '../../app/constants/storage_keys.dart';
import 'secure_storage.dart';

/// Persists auth tokens in encrypted secure storage.
class TokenStorage {
  TokenStorage(this._secure);

  final SecureStorage _secure;

  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
    DateTime? expiry,
  }) async {
    await _secure.write(StorageKeys.accessToken, accessToken);
    if (refreshToken != null) {
      await _secure.write(StorageKeys.refreshToken, refreshToken);
    }
    if (expiry != null) {
      await _secure.write(
        StorageKeys.tokenExpiry,
        expiry.toIso8601String(),
      );
    }
  }

  Future<String?> getAccessToken() => _secure.read(StorageKeys.accessToken);

  Future<String?> getRefreshToken() => _secure.read(StorageKeys.refreshToken);

  Future<DateTime?> getExpiry() async {
    final raw = await _secure.read(StorageKeys.tokenExpiry);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<bool> hasValidToken() async {
    final token = await getAccessToken();
    if (token == null || token.isEmpty) return false;
    final expiry = await getExpiry();
    if (expiry == null) return true; // no expiry info -> assume valid
    return expiry.isAfter(DateTime.now());
  }

  Future<void> clear() async {
    await _secure.delete(StorageKeys.accessToken);
    await _secure.delete(StorageKeys.refreshToken);
    await _secure.delete(StorageKeys.tokenExpiry);
  }
}
