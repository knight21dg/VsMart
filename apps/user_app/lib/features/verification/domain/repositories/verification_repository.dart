import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/verification_application.dart';
import '../entities/verification_draft.dart';
import '../entities/verification_result.dart';

/// Remote verification operations: submit an application and read its status.
abstract interface class VerificationRepository {
  /// Submit the completed [draft] for review; returns the created application.
  Future<Either<Failure, VerificationApplication>> submit(
      VerificationDraft draft);

  /// Submit the residence proof photo plus device-captured GPS coordinates.
  Future<Either<Failure, VerificationApplication>> submitResidence({
    required String photoPath,
    required double latitude,
    required double longitude,
  });

  /// Fetch the latest application status for the current user.
  Future<Either<Failure, VerificationApplication>> getApplication();

  /// Re-open a rejected application for another attempt.
  Future<Either<Failure, VerificationApplication>> retry();

  /// Verify a PAN against the government source.
  Future<Either<Failure, VerificationResult>> verifyPan({
    required String pan,
    required String name,
    required bool consent,
  });

  /// Send the Aadhaar OTP to the linked mobile (returns a pending reference id).
  Future<Either<Failure, VerificationResult>> sendAadhaarOtp({
    required String aadhaar,
  });

  /// Verify the Aadhaar OTP for a prior reference id.
  Future<Either<Failure, VerificationResult>> verifyAadhaarOtp({
    required String referenceId,
    required String otp,
    required String aadhaar,
  });
}
