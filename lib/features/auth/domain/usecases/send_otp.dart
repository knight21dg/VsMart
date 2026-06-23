import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/utils/usecase.dart';
import '../repositories/otp_repository.dart';

/// Sends an OTP to a phone number; returns the verification id.
class SendOtp implements UseCase<String, String> {
  const SendOtp(this._repository);

  final OtpRepository _repository;

  @override
  Future<Either<Failure, String>> call(String phone) =>
      _repository.sendOtp(phone);
}
