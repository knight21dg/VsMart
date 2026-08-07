import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/utils/usecase.dart';
import '../entities/auth_token.dart';
import '../repositories/auth_repository.dart';
import '../repositories/otp_repository.dart';

class VerifyOtpParams extends Equatable {
  const VerifyOtpParams({
    required this.phone,
    required this.code,
    this.verificationId,
  });

  final String phone;
  final String code;
  final String? verificationId;

  @override
  List<Object?> get props => [phone, code, verificationId];
}

/// Verifies an OTP and persists the resulting session on success.
class VerifyOtp implements UseCase<AuthResult, VerifyOtpParams> {
  const VerifyOtp(this._otpRepository, this._authRepository);

  final OtpRepository _otpRepository;
  final AuthRepository _authRepository;

  @override
  Future<Either<Failure, AuthResult>> call(VerifyOtpParams params) async {
    final result = await _otpRepository.verifyOtp(
      phone: params.phone,
      code: params.code,
      verificationId: params.verificationId,
    );
    return result.fold(
      (failure) async => Left<Failure, AuthResult>(failure),
      (auth) async {
        final persisted = await _authRepository.persistSession(auth.token);
        return persisted.map((_) => auth);
      },
    );
  }
}
