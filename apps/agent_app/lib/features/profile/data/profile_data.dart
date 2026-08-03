import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/providers.dart';

String _str(dynamic v) => v == null ? '' : v.toString();

/// The signed-in agent's account (GET/PATCH /users/me).
class UserProfile extends Equatable {
  const UserProfile({
    required this.id,
    required this.phone,
    required this.name,
    required this.email,
    required this.role,
    required this.avatarUrl,
    required this.kycStatus,
  });

  final String id;
  final String phone;
  final String name;
  final String email;
  final String role;
  final String avatarUrl;
  final String kycStatus;

  String get displayName => name.isNotEmpty ? name : phone;

  factory UserProfile.fromMap(Map<String, dynamic> m) => UserProfile(
        id: _str(m['id']),
        phone: _str(m['phone']),
        name: _str(m['name']),
        email: _str(m['email']),
        role: _str(m['role']),
        avatarUrl: _str(m['avatarUrl'] ?? m['avatar_url']),
        kycStatus: _str(m['kycStatus'] ?? m['kyc_status']),
      );

  @override
  List<Object?> get props => [id, phone, name, email, role, avatarUrl, kycStatus];
}

/// Thin repository over [Api] for the agent's account. Non-2xx → [ApiException].
class ProfileRepo {
  ProfileRepo(this._api);
  final Api _api;

  Future<UserProfile> me() async {
    final res = _api.ensureOk(await _api.get('/users/me'));
    return UserProfile.fromMap(_api.obj(res.data));
  }

  /// PATCH /users/me {name?, email?} → the updated profile.
  Future<UserProfile> update({String? name, String? email}) async {
    final res = _api.ensureOk(await _api.patch('/users/me', data: {
      if (name != null) 'name': name,
      if (email != null) 'email': email,
    }));
    return UserProfile.fromMap(_api.obj(res.data));
  }
}

final profileRepoProvider =
    Provider<ProfileRepo>((ref) => ProfileRepo(ref.watch(apiProvider)));

final userProfileProvider = FutureProvider.autoDispose<UserProfile>(
  (ref) => ref.watch(profileRepoProvider).me(),
);
