import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_handler.dart';
import '../../../../core/errors/failures.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../auth/presentation/providers/current_user_provider.dart';
import '../../../payments/presentation/payment_providers.dart';
import '../../data/datasources/credit_backend_data_source.dart';
import '../../data/datasources/credit_data_source.dart';
import '../../data/repositories/credit_repository_impl.dart';
import '../../domain/entities/credit_account.dart';
import '../../domain/entities/credit_payment_result.dart';
import '../../domain/entities/credit_transaction.dart';
import '../../domain/repositories/credit_repository.dart';

T _unwrap<T>(Either<Failure, T> either) =>
    either.fold((f) => throw f, (value) => value);

final creditDataSourceProvider = Provider<CreditDataSource>(
  (ref) => CreditBackendDataSource(ref.watch(apiClientProvider)),
);

final creditRepositoryProvider = Provider<CreditRepository>(
  (ref) => CreditRepositoryImpl(
    dataSource: ref.watch(creditDataSourceProvider),
    networkInfo: ref.watch(networkInfoProvider),
  ),
);

final creditAccountProvider = FutureProvider<CreditAccount>(
  (ref) async => _unwrap(await ref.watch(creditRepositoryProvider).getAccount()),
);

final creditTransactionsProvider = FutureProvider<List<CreditTransaction>>(
  (ref) async =>
      _unwrap(await ref.watch(creditRepositoryProvider).getTransactions()),
);

/// Holds the most recent successful repayment so the success screen can render
/// it after navigation.
final lastPaymentResultProvider = StateProvider<CreditPaymentResult?>(
  (ref) => null,
);

/// Holds the [Failure] from the most recent failed repayment so the UI can route
/// it through the actionable error presenter. Cleared at the start of each pay.
final lastPaymentFailureProvider = StateProvider<Failure?>((ref) => null);

/// Drives a repayment; `state` is the in-flight flag. On success it stores the
/// result in [lastPaymentResultProvider] and refreshes the account.
class CreditPaymentController extends Notifier<bool> {
  @override
  bool build() => false;

  Future<bool> pay({required num amount, required String method}) async {
    state = true;
    ref.read(lastPaymentFailureProvider.notifier).state = null;
    try {
      final phone = ref.read(currentUserProvider)?.phone ?? '';
      // Records the repayment on the server (/credit/repay) and settles it via
      // Razorpay when a live gateway is configured (auto-settled in mock mode).
      final outcome = await ref.read(paymentServiceProvider).payRepayment(
            amount: amount,
            method: _apiMethod(method),
            phone: phone,
          );
      if (!outcome.success) {
        state = false;
        return false;
      }
      // Re-read the account so the success screen shows the post-payment balance.
      final account = _unwrap(await ref.read(creditRepositoryProvider).getAccount());
      ref.read(lastPaymentResultProvider.notifier).state = CreditPaymentResult(
        transactionId: outcome.paymentId ?? outcome.gatewayPaymentId ?? '',
        amountPaid: amount,
        method: method,
        account: account,
      );
      ref.invalidate(creditAccountProvider);
      ref.invalidate(creditTransactionsProvider);
      state = false;
      return true;
    } catch (e) {
      // Surface the (possibly actionable) failure so the screen can present it.
      ref.read(lastPaymentFailureProvider.notifier).state =
          ErrorHandler.handle(e);
      state = false;
      return false;
    }
  }

  /// Maps a UI method label to a backend repay method (upi/card/netbanking).
  String _apiMethod(String label) {
    final l = label.toLowerCase();
    if (l.contains('card')) return 'card';
    if (l.contains('net') || l.contains('bank')) return 'netbanking';
    return 'upi'; // UPI, QR Code, Payment Link
  }
}

final creditPaymentControllerProvider =
    NotifierProvider<CreditPaymentController, bool>(CreditPaymentController.new);
