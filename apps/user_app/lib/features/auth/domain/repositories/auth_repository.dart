import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/auth_token.dart';
import '../entities/user.dart';

/// Authentication operations (login/register/session). OTP send/verify live in
/// [OtpRepository] to keep responsibilities focused.
abstract interface class AuthRepository {
  /// Complete profile registration for a freshly authenticated phone number.
  Future<Either<Failure, User>> register({
    required String name,
    String? email,
    String? referralCode,
  });

  /// Persist tokens locally (called after a successful verify).
  Future<Either<Failure, Unit>> persistSession(AuthToken token);

  /// Whether a non-expired token exists in secure storage.
  Future<bool> hasValidSession();

  /// Revoke the session server-side (best-effort) and clear local credentials.
  Future<Either<Failure, Unit>> logout();
}
