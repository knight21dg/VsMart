// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$UserModelImpl _$$UserModelImplFromJson(Map<String, dynamic> json) =>
    _$UserModelImpl(
      id: json['id'] as String,
      phone: json['phone'] as String? ?? '',
      name: json['name'] as String? ?? '',
      email: json['email'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      kycStatus: json['kyc_status'] as String?,
      creditEnabled: json['credit_enabled'] as bool? ?? false,
      role: json['role'] as String? ?? 'customer',
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
    );

Map<String, dynamic> _$$UserModelImplToJson(_$UserModelImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'phone': instance.phone,
      'name': instance.name,
      'email': instance.email,
      'avatar_url': instance.avatarUrl,
      'kyc_status': instance.kycStatus,
      'credit_enabled': instance.creditEnabled,
      'role': instance.role,
      'created_at': instance.createdAt?.toIso8601String(),
    };
