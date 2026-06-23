import '../../domain/entities/verification_application.dart';
import '../../domain/entities/verification_draft.dart';

/// Data-source contract for verification, implemented by
/// [VerificationBackendDataSource] (the `/kyc/*` API).
abstract interface class VerificationDataSource {
  Future<VerificationApplication> submit(VerificationDraft draft);
  Future<VerificationApplication> getApplication();
}
