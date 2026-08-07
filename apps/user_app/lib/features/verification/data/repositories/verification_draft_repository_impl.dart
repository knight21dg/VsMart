import '../../../../app/constants/storage_keys.dart';
import '../../../../core/storage/hive_service.dart';
import '../../domain/entities/verification_draft.dart';
import '../../domain/repositories/verification_draft_repository.dart';
import '../models/verification_draft_model.dart';

/// [VerificationDraftRepository] backed by the Hive `verificationBox`. Stores the
/// draft as a single JSON map so it survives restarts and offline gaps.
class VerificationDraftRepositoryImpl implements VerificationDraftRepository {
  VerificationDraftRepositoryImpl(this._hive);

  final HiveService _hive;

  @override
  VerificationDraft load() {
    final raw = _hive.verificationBox.get(StorageKeys.verificationDraft);
    if (raw is Map) {
      return VerificationDraftModel.fromJson(Map<String, dynamic>.from(raw));
    }
    return const VerificationDraft();
  }

  @override
  Future<void> save(VerificationDraft draft) => _hive.verificationBox
      .put(StorageKeys.verificationDraft, VerificationDraftModel.toJson(draft));

  @override
  Future<void> clear() =>
      _hive.verificationBox.delete(StorageKeys.verificationDraft);
}
