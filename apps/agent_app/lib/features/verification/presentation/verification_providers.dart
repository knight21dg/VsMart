import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/verification_data.dart';

final verificationRepoProvider = Provider<VerificationRepo>(
  (ref) => VerificationRepo(ref.watch(apiProvider)),
);

/// Field-verification tasks for the signed-in agent (GET /verification/tasks).
final verificationTasksProvider =
    FutureProvider.autoDispose<List<VerificationTask>>(
  (ref) => ref.watch(verificationRepoProvider).tasks(),
);

/// Full detail for a single task (GET /verification/tasks/{id}). Keyed by id so
/// the detail screen refreshes just this record after each step.
final verificationTaskDetailProvider =
    FutureProvider.autoDispose.family<VerificationTask, String>(
  (ref, id) => ref.watch(verificationRepoProvider).detail(id),
);
