import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/auth_token.dart';

/// Phone OTP send/verify operations.
abstract interface class OtpRepository {
  /// Request an OTP for [phone]. Returns a verification id / token the backend
  /// expects back on verify (empty string if not used).
  Future<Either<Failure, String>> sendOtp(String phone);

  /// Verify [code] for [phone]. On success returns tokens + new-user flag.
  Future<Either<Failure, AuthResult>> verifyOtp({
    required String phone,
    required String code,
    String? verificationId,
  });
}
