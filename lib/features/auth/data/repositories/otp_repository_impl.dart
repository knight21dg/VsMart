import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/network/base_repository.dart';
import '../../../../core/network/network_info.dart';
import '../../domain/entities/auth_token.dart';
import '../../domain/repositories/otp_repository.dart';
import '../datasources/auth_remote_datasource.dart';

class OtpRepositoryImpl with BaseRepository implements OtpRepository {
  OtpRepositoryImpl({required this.remote, required this.networkInfo});

  final AuthRemoteDataSource remote;

  @override
  final NetworkInfo networkInfo;

  @override
  Future<Either<Failure, String>> sendOtp(String phone) =>
      guard(() => remote.sendOtp(phone));

  @override
  Future<Either<Failure, AuthResult>> verifyOtp({
    required String phone,
    required String code,
    String? verificationId,
  }) =>
      guard(() async {
        final res = await remote.verifyOtp(
          phone: phone,
          code: code,
          verificationId: verificationId,
        );
        return AuthResult(
          token: res.token.toEntity(),
          isNewUser: res.isNewUser,
        );
      });
}
