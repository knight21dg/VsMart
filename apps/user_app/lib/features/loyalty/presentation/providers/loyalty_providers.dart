import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_handler.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../data/loyalty_data.dart';

final loyaltyDataSourceProvider = Provider<LoyaltyRemoteDataSource>(
  (ref) => LoyaltyRemoteDataSource(ref.watch(apiClientProvider)),
);

/// The signed-in user's points balance, lifetime earned, and tier.
///
/// Errors are normalised to a typed [Failure] via [ErrorHandler] so the UI's
/// [VSErrorView] receives a real failure (a raw DioException would downcast to
/// null and lose the backend message).
final loyaltyStatusProvider = FutureProvider<LoyaltyStatus>((ref) async {
  try {
    return await ref.watch(loyaltyDataSourceProvider).getStatus();
  } catch (e) {
    throw ErrorHandler.handle(e);
  }
});

/// The points ledger (earn / redeem / expire history), newest first.
final loyaltyLedgerProvider = FutureProvider<List<PointsEntry>>((ref) async {
  try {
    return await ref.watch(loyaltyDataSourceProvider).getLedger();
  } catch (e) {
    throw ErrorHandler.handle(e);
  }
});
