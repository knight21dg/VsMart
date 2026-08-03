import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/batch_data.dart';
import '../data/deliveries_data.dart';
import '../data/location_service.dart';

final deliveriesRepoProvider = Provider<DeliveriesRepo>(
  (ref) => DeliveriesRepo(ref.watch(apiProvider)),
);

final batchRepoProvider = Provider<BatchRepo>(
  (ref) => BatchRepo(ref.watch(apiProvider)),
);

/// The agent's active guided-route batch (GET /deliveries/batch/current), or null.
final currentBatchProvider = FutureProvider.autoDispose<RouteBatch?>(
  (ref) => ref.watch(batchRepoProvider).current(),
);

/// Single shared location source for the delivery flow (see [LocationService]).
final locationServiceProvider = Provider<LocationService>(
  (ref) => LocationService(),
);

/// Active tasks currently assigned to the signed-in agent
/// (GET /deliveries/assigned).
final assignedDeliveriesProvider =
    FutureProvider.autoDispose<List<AgentDelivery>>(
  (ref) => ref.watch(deliveriesRepoProvider).assigned(),
);

/// Full detail for a single task (GET /deliveries/{id}). Keyed by task id so
/// the detail screen can refresh just this record after each state transition.
final deliveryDetailProvider =
    FutureProvider.autoDispose.family<AgentDelivery, String>(
  (ref, id) => ref.watch(deliveriesRepoProvider).detail(id),
);
