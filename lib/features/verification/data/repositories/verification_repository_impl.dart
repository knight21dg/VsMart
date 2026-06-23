import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/network/base_repository.dart';
import '../../../../core/network/network_info.dart';
import '../../domain/entities/verification_application.dart';
import '../../domain/entities/verification_draft.dart';
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
  Future<Either<Failure, VerificationApplication>> getApplication() =>
      guard(dataSource.getApplication, requireConnection: false);
}
