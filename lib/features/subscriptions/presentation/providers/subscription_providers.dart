import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/core_providers.dart';
import '../../data/subscription_data.dart';

final subscriptionDataSourceProvider = Provider<SubscriptionRemoteDataSource>(
  (ref) => SubscriptionRemoteDataSource(ref.watch(apiClientProvider)),
);

/// The signed-in user's recurring subscriptions.
final subscriptionsProvider = FutureProvider<List<Subscription>>(
  (ref) => ref.watch(subscriptionDataSourceProvider).list(),
);
