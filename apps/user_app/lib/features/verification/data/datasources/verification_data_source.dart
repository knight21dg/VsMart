import '../../domain/entities/verification_application.dart';
import '../../domain/entities/verification_draft.dart';
import '../../domain/entities/verification_result.dart';

/// Data-source contract for verification, implemented by
/// [VerificationBackendDataSource] (the `/kyc/*` API).
abstract interface class VerificationDataSource {
  Future<VerificationApplication> submit(VerificationDraft draft);

  /// Submit the residence proof photo plus the device-captured GPS coordinates
  /// to `POST /kyc/submit` (document type `residence`).
  Future<VerificationApplication> submitResidence({
    required String photoPath,
    required double latitude,
    required double longitude,
  });

  Future<VerificationApplication> getApplication();

  /// Re-open a rejected application so the customer can attempt verification again.
  Future<VerificationApplication> retry();

  /// Verify a PAN against the government source. [name] is matched against the
  /// PAN holder; [consent] must be true (DPDP/PAN consent).
  Future<VerificationResult> verifyPan({
    required String pan,
    required String name,
    required bool consent,
  });

  /// Trigger the Aadhaar OTP to the Aadhaar-linked mobile. Returns a PENDING
  /// result carrying the request reference id to submit alongside the OTP.
  Future<VerificationResult> sendAadhaarOtp({required String aadhaar});

  /// Verify the Aadhaar OTP for a prior [referenceId].
  Future<VerificationResult> verifyAadhaarOtp({
    required String referenceId,
    required String otp,
    required String aadhaar,
  });
}
