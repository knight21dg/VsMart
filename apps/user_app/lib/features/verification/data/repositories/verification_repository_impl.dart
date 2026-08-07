import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/network/base_repository.dart';
import '../../../../core/network/network_info.dart';
import '../../domain/entities/verification_application.dart';
import '../../domain/entities/verification_draft.dart';
import '../../domain/entities/verification_result.dart';
import '../../domain/repositories/verification_repository.dart';
import '../datasources/verification_data_source.dart';

/// [VerificationRepository] backed by a [VerificationDataSource]. Errors
/// normalise to [Failure] via [BaseRepository.guard].
class VerificationRepositoryImpl
    with BaseRepository
    implements VerificationRepository {
  VerificationRepositoryImpl({
    required this.dataSource,
    required this.networkInfo,
  });

  final VerificationDataSource dataSource;

  @override
  final NetworkInfo networkInfo;

  @override
  Future<Either<Failure, VerificationApplication>> submit(
          VerificationDraft draft) =>
      guard(() => dataSource.submit(draft), requireConnection: false);

  @override
  Future<Either<Failure, VerificationApplication>> submitResidence({
    required String photoPath,
    required double latitude,
    required double longitude,
  }) =>
      guard(
        () => dataSource.submitResidence(
          photoPath: photoPath,
          latitude: latitude,
          longitude: longitude,
        ),
        requireConnection: false,
      );

  @override
  Future<Either<Failure, VerificationApplication>> getApplication() =>
      guard(dataSource.getApplication, requireConnection: false);

  @override
  Future<Either<Failure, VerificationApplication>> retry() =>
      guard(dataSource.retry);

  @override
  Future<Either<Failure, VerificationResult>> verifyPan({
    required String pan,
    required String name,
    required bool consent,
  }) =>
      guard(() => dataSource.verifyPan(pan: pan, name: name, consent: consent));

  @override
  Future<Either<Failure, VerificationResult>> sendAadhaarOtp({
    required String aadhaar,
  }) =>
      guard(() => dataSource.sendAadhaarOtp(aadhaar: aadhaar));

  @override
  Future<Either<Failure, VerificationResult>> verifyAadhaarOtp({
    required String referenceId,
    required String otp,
    required String aadhaar,
  }) =>
      guard(() => dataSource.verifyAadhaarOtp(
            referenceId: referenceId,
            otp: otp,
            aadhaar: aadhaar,
          ));
}
