import 'package:equatable/equatable.dart';

/// KYC verification stages for a customer.
enum KycStatus { notStarted, pending, verified, rejected }

/// Core domain representation of a VS Mart customer. UI and business logic
/// depend on this entity, never on the data-layer model directly.
class User extends Equatable {
  const User({
    required this.id,
    required this.phone,
    this.name = '',
    this.email,
    this.avatarUrl,
    this.kycStatus = KycStatus.notStarted,
    this.creditEnabled = false,
    this.createdAt,
  });

  final String id;
  final String phone;
  final String name;
  final String? email;
  final String? avatarUrl;
  final KycStatus kycStatus;
  final bool creditEnabled;
  final DateTime? createdAt;

  bool get isKycVerified => kycStatus == KycStatus.verified;
  bool get hasProfile => name.trim().isNotEmpty;

  User copyWith({
    String? id,
    String? phone,
    String? name,
    String? email,
    String? avatarUrl,
    KycStatus? kycStatus,
    bool? creditEnabled,
    DateTime? createdAt,
  }) {
    return User(
      id: id ?? this.id,
      phone: phone ?? this.phone,
      name: name ?? this.name,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      kycStatus: kycStatus ?? this.kycStatus,
      creditEnabled: creditEnabled ?? this.creditEnabled,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props =>
      [id, phone, name, email, avatarUrl, kycStatus, creditEnabled, createdAt];
}
