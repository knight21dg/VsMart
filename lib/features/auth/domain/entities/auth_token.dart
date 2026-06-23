import 'package:equatable/equatable.dart';

/// Auth tokens returned by the backend after a successful login/verify.
class AuthToken extends Equatable {
  const AuthToken({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiresAt;

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  @override
  List<Object?> get props => [accessToken, refreshToken, expiresAt];
}

/// Result of OTP verification: tokens plus whether the user must complete
/// registration/KYC before entering the app.
class AuthResult extends Equatable {
  const AuthResult({
    required this.token,
    required this.isNewUser,
  });

  final AuthToken token;
  final bool isNewUser;

  @override
  List<Object?> get props => [token, isNewUser];
}
