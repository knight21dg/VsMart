import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'data/returns_data.dart';

final returnsRepoProvider = Provider<ReturnsRepo>(
  (ref) => ReturnsRepo(ref.watch(apiProvider)),
);

/// Open return pickups assigned to the signed-in agent
/// (GET /agent/return-pickups). Kept fresh by [TaskSync].
final assignedReturnPickupsProvider =
    FutureProvider.autoDispose<List<ReturnPickup>>(
  (ref) => ref.watch(returnsRepoProvider).assigned(),
);

/// Pickups this agent already closed (GET /agent/return-pickups/history).
final returnPickupHistoryProvider =
    FutureProvider.autoDispose<List<ReturnPickup>>(
  (ref) => ref.watch(returnsRepoProvider).history(),
);

/// Full detail for one pickup, keyed by task id so the detail screen can
/// refresh just that record after each state transition.
final returnPickupDetailProvider =
    FutureProvider.autoDispose.family<ReturnPickup, String>(
  (ref, id) => ref.watch(returnsRepoProvider).detail(id),
);
