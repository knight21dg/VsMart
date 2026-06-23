import '../entities/verification_draft.dart';

/// Local persistence for the in-progress verification draft (offline-first).
abstract interface class VerificationDraftRepository {
  /// Load the saved draft, or a fresh empty draft if none exists.
  VerificationDraft load();

  /// Persist the current draft locally.
  Future<void> save(VerificationDraft draft);

  /// Remove the saved draft (e.g. after successful submission).
  Future<void> clear();
}
