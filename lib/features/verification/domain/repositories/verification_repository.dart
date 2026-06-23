import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/verification_application.dart';
import '../entities/verification_draft.dart';

/// Remote verification operations: submit an application and read its status.
abstract interface class VerificationRepository {
  /// Submit the completed [draft] for review; returns the created application.
  Future<Either<Failure, VerificationApplication>> submit(
      VerificationDraft draft);

  /// Fetch the latest application status for the current user.
  Future<Either<Failure, VerificationApplication>> getApplication();
}
