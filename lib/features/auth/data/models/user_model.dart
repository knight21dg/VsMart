import 'package:freezed_annotation/freezed_annotation.dart';

import '../../domain/entities/user.dart';

part 'user_model.freezed.dart';
part 'user_model.g.dart';

/// Data-layer model for [User]. Handles (de)serialization and maps to/from the
/// domain entity.
@freezed
class UserModel with _$UserModel {
  const UserModel._();

  const factory UserModel({
    required String id,
    @JsonKey(defaultValue: '') @Default('') String phone,
    @JsonKey(defaultValue: '') @Default('') String name,
    String? email,
    @JsonKey(name: 'avatar_url') String? avatarUrl,
    @JsonKey(name: 'kyc_status') String? kycStatus,
    @JsonKey(name: 'credit_enabled') @Default(false) bool creditEnabled,
    @JsonKey(name: 'role', defaultValue: 'customer') @Default('customer') String role,
    @JsonKey(name: 'created_at') DateTime? createdAt,
  }) = _UserModel;

  factory UserModel.fromJson(Map<String, dynamic> json) =>
      _$UserModelFromJson(json);

  factory UserModel.fromEntity(User user) => UserModel(
        id: user.id,
        phone: user.phone,
        name: user.name,
        email: user.email,
        avatarUrl: user.avatarUrl,
        kycStatus: user.kycStatus.name,
        creditEnabled: user.creditEnabled,
        createdAt: user.createdAt,
      );

  User toEntity() => User(
        id: id,
        phone: phone,
        name: name,
        email: email,
        avatarUrl: avatarUrl,
        kycStatus: _parseKyc(kycStatus),
        creditEnabled: creditEnabled,
        createdAt: createdAt,
      );

  static KycStatus _parseKyc(String? raw) {
    switch (raw?.toLowerCase()) {
      case 'verified':
      case 'approved':
        return KycStatus.verified;
      case 'pending':
      case 'in_review':
        return KycStatus.pending;
      case 'rejected':
      case 'failed':
        return KycStatus.rejected;
      default:
        return KycStatus.notStarted;
    }
  }
}
