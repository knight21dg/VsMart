import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/providers/session_provider.dart';
import '../../data/datasources/verification_backend_data_source.dart';
import '../../data/datasources/verification_data_source.dart';
import '../../data/repositories/verification_draft_repository_impl.dart';
import '../../data/repositories/verification_repository_impl.dart';
import '../../domain/entities/verification_application.dart';
import '../../domain/entities/verification_draft.dart';
import '../../domain/entities/verification_enums.dart';
import '../../domain/repositories/verification_draft_repository.dart';
import '../../domain/repositories/verification_repository.dart';

T _unwrap<T>(Either<Failure, T> either) =>
    either.fold((f) => throw f, (value) => value);

/// ---------------------------------------------------------------------------
/// Wiring
/// ---------------------------------------------------------------------------
final verificationDraftRepositoryProvider =
    Provider<VerificationDraftRepository>(
  (ref) => VerificationDraftRepositoryImpl(ref.watch(hiveServiceProvider)),
);

final verificationDataSourceProvider = Provider<VerificationDataSource>(
  (ref) => VerificationBackendDataSource(ref.watch(apiClientProvider)),
);

final verificationRepositoryProvider = Provider<VerificationRepository>(
  (ref) => VerificationRepositoryImpl(
    dataSource: ref.watch(verificationDataSourceProvider),
    networkInfo: ref.watch(networkInfoProvider),
  ),
);

/// ---------------------------------------------------------------------------
/// Draft controller — holds the live draft, auto-persisting every change so the
/// application can be resumed after an app kill or offline gap.
/// ---------------------------------------------------------------------------
class VerificationController extends Notifier<VerificationDraft> {
  VerificationDraftRepository get _drafts =>
      ref.read(verificationDraftRepositoryProvider);

  @override
  VerificationDraft build() => _drafts.load();

  void _commit(VerificationDraft draft) {
    state = draft;
    _drafts.save(draft); // fire-and-forget local persistence
  }

  void setIdentityNumbers({required String aadhaar, required String pan}) =>
      _commit(state.copyWith(aadhaarNumber: aadhaar, panNumber: pan));

  void setAadhaarFront(String path) =>
      _commit(state.copyWith(aadhaarFrontPath: path));
  void setAadhaarBack(String path) =>
      _commit(state.copyWith(aadhaarBackPath: path));
  void setPan(String path) => _commit(state.copyWith(panPath: path));

  void setSelfie(String path) => _commit(state.copyWith(selfiePath: path));

  /// Partial credit-application update — autosaves each field as the user fills
  /// the form (any omitted field keeps its current value).
  void patchCredit({
    String? occupation,
    num? monthlyIncome,
    int? familyMembers,
    HouseType? houseType,
    Ownership? ownership,
    num? requestedLimit,
  }) =>
      _commit(state.copyWith(
        occupation: occupation,
        monthlyIncome: monthlyIncome,
        familyMembers: familyMembers,
        houseType: houseType,
        ownership: ownership,
        requestedLimit: requestedLimit,
      ));

  /// Submit the draft for review. On success the local draft is cleared and the
  /// created application is stored in [submittedApplicationProvider].
  Future<VerificationApplication?> submit() async {
    final result = await ref.read(verificationRepositoryProvider).submit(state);
    return result.fold((_) => null, (application) {
      ref.read(submittedApplicationProvider.notifier).state = application;
      _drafts.clear();
      state = state.copyWith(status: VerificationStatus.pending);
      // Reflect the pending verification in the session so route guards hold
      // the user at the status screen until a decision is made.
      final user = ref.read(sessionControllerProvider).user;
      if (user != null) {
        ref
            .read(sessionControllerProvider.notifier)
            .setUser(user.copyWith(kycStatus: KycStatus.pending));
      }
      return application;
    });
  }

  void reset() {
    _drafts.clear();
    state = const VerificationDraft();
  }
}

final verificationControllerProvider =
    NotifierProvider<VerificationController, VerificationDraft>(
        VerificationController.new);

/// The application created by the most recent submission (for the Submitted
/// screen).
final submittedApplicationProvider =
    StateProvider<VerificationApplication?>((ref) => null);

/// The current application status from the backend (for the Status screen).
final verificationStatusProvider = FutureProvider<VerificationApplication>(
  (ref) async =>
      _unwrap(await ref.watch(verificationRepositoryProvider).getApplication()),
);
