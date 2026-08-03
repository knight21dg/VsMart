import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'data/collections_data.dart';

final collectionsRepoProvider = Provider<CollectionsRepo>(
  (ref) => CollectionsRepo(ref.watch(apiProvider)),
);

/// Active cash-recovery tasks currently assigned to the signed-in agent
/// (GET /collections/assigned).
final assignedCollectionsProvider =
    FutureProvider.autoDispose<List<AgentCollection>>(
  (ref) => ref.watch(collectionsRepoProvider).assigned(),
);

/// Full detail for a single task (GET /collections/{id}). Keyed by task id so
/// the detail screen can refresh just this record after each state transition.
final collectionDetailProvider =
    FutureProvider.autoDispose.family<AgentCollection, String>(
  (ref, id) => ref.watch(collectionsRepoProvider).detail(id),
);
