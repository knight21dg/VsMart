import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypted storage for the agent's JWT access/refresh tokens.
class TokenStore {
  TokenStore([this._s = const FlutterSecureStorage()]);

  final FlutterSecureStorage _s;

  static const _access = 'agent_access';
  static const _refresh = 'agent_refresh';

  Future<void> save({required String access, String? refresh}) async {
    await _s.write(key: _access, value: access);
    if (refresh != null) await _s.write(key: _refresh, value: refresh);
  }

  Future<String?> get access => _s.read(key: _access);
  Future<String?> get refresh => _s.read(key: _refresh);

  Future<bool> get isLoggedIn async => (await access)?.isNotEmpty ?? false;

  Future<void> clear() async {
    await _s.delete(key: _access);
    await _s.delete(key: _refresh);
  }
}
