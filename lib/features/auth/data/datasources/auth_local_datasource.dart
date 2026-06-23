import '../../../../core/storage/local_user_storage.dart';
import '../../../../core/storage/token_storage.dart';
import '../../domain/entities/auth_token.dart';
import '../models/user_model.dart';

/// Local persistence for auth: tokens (secure) and cached user (Hive).
abstract interface class AuthLocalDataSource {
  Future<void> saveToken(AuthToken token);
  Future<bool> hasValidToken();
  Future<void> cacheUser(UserModel user);
  UserModel? getCachedUser();
  bool get isLoggedIn;
  Future<void> clear();
}

class AuthLocalDataSourceImpl implements AuthLocalDataSource {
  AuthLocalDataSourceImpl(this._tokenStorage, this._userStorage);

  final TokenStorage _tokenStorage;
  final LocalUserStorage _userStorage;

  @override
  Future<void> saveToken(AuthToken token) => _tokenStorage.saveTokens(
        accessToken: token.accessToken,
        refreshToken: token.refreshToken,
        expiry: token.expiresAt,
      );

  @override
  Future<bool> hasValidToken() => _tokenStorage.hasValidToken();

  @override
  Future<void> cacheUser(UserModel user) =>
      _userStorage.saveUser(user.toJson());

  @override
  UserModel? getCachedUser() {
    final json = _userStorage.getUser();
    if (json == null) return null;
    try {
      return UserModel.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  @override
  bool get isLoggedIn => _userStorage.isLoggedIn;

  @override
  Future<void> clear() async {
    await _tokenStorage.clear();
    await _userStorage.clear();
  }
}
