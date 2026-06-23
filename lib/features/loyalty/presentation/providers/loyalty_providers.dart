import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/core_providers.dart';
import '../../data/loyalty_data.dart';

final loyaltyDataSourceProvider = Provider<LoyaltyRemoteDataSource>(
  (ref) => LoyaltyRemoteDataSource(ref.watch(apiClientProvider)),
);

/// The signed-in user's points balance, lifetime earned, and tier.
final loyaltyStatusProvider = FutureProvider<LoyaltyStatus>(
  (ref) => ref.watch(loyaltyDataSourceProvider).getStatus(),
);

/// The points ledger (earn / redeem / expire history), newest first.
final loyaltyLedgerProvider = FutureProvider<List<PointsEntry>>(
  (ref) => ref.watch(loyaltyDataSourceProvider).getLedger(),
);
