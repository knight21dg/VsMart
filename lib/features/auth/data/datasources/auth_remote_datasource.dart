import '../../../../app/constants/api_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/api_client.dart';
import '../models/auth_token_model.dart';
import '../models/user_model.dart';

/// Remote auth API surface. Returns typed models; throws on error (mapped to
/// failures in the repository via [ApiClient]'s error interceptor).
abstract interface class AuthRemoteDataSource {
  Future<String> sendOtp(String phone);
  Future<({AuthTokenModel token, bool isNewUser})> verifyOtp({
    required String phone,
    required String code,
    String? verificationId,
  });
  Future<UserModel> register({
    required String name,
    String? email,
    String? referralCode,
  });
  Future<UserModel> getCurrentUser();
  Future<UserModel> updateProfile(Map<String, dynamic> body);
  Future<void> logout();
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  AuthRemoteDataSourceImpl(this._client);

  final ApiClient _client;

  Map<String, dynamic> _data(dynamic raw) {
    if (raw is Map && raw['data'] is Map) {
      return Map<String, dynamic>.from(raw['data'] as Map);
    }
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  @override
  Future<String> sendOtp(String phone) async {
    final res = await _client.post<dynamic>(
      ApiConstants.sendOtp,
      data: {'phone': phone},
      options: ApiClient.noAuth(),
    );
    return _data(res.data)['verification_id']?.toString() ?? '';
  }

  @override
  Future<({AuthTokenModel token, bool isNewUser})> verifyOtp({
    required String phone,
    required String code,
    String? verificationId,
  }) async {
    final res = await _client.post<dynamic>(
      ApiConstants.verifyOtp,
      data: {
        'phone': phone,
        'otp': code,
        // Backend requires verification_id (CharField, non-blank). Always send
        // the id returned by /auth/otp/send so the contract is satisfied.
        'verification_id': verificationId ?? '',
      },
      options: ApiClient.noAuth(),
    );
    final data = _data(res.data);
    // Defensive: a well-formed success always carries an access token. If it's
    // missing we surface a clean error instead of a raw typecast crash.
    if (data['access_token'] is! String ||
        (data['access_token'] as String).isEmpty) {
      throw const ServerException('Verification failed. Please try again.');
    }
    return (
      token: AuthTokenModel.fromJson(Map<String, dynamic>.from(data)),
      isNewUser: data['is_new_user'] as bool? ?? false,
    );
  }

  @override
  Future<UserModel> register({
    required String name,
    String? email,
    String? referralCode,
  }) async {
    final res = await _client.post<dynamic>(
      ApiConstants.register,
      data: {
        'name': name,
        if (email != null && email.isNotEmpty) 'email': email,
        if (referralCode != null && referralCode.isNotEmpty)
          'referral_code': referralCode,
      },
    );
    return UserModel.fromJson(_data(res.data));
  }

  @override
  Future<UserModel> getCurrentUser() async {
    final res = await _client.get<dynamic>(ApiConstants.me);
    return UserModel.fromJson(_data(res.data));
  }

  @override
  Future<UserModel> updateProfile(Map<String, dynamic> body) async {
    final res = await _client.patch<dynamic>(
      ApiConstants.updateProfile,
      data: body,
    );
    return UserModel.fromJson(_data(res.data));
  }

  @override
  Future<void> logout() => _client.post<dynamic>(ApiConstants.logout);
}
