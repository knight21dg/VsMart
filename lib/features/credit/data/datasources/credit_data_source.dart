import '../../domain/entities/credit_account.dart';
import '../../domain/entities/credit_payment_result.dart';
import '../../domain/entities/credit_transaction.dart';

/// Data-source contract for the credit module. Implemented by
/// [CreditBackendDataSource] (the `/credit/*` API).
abstract interface class CreditDataSource {
  Future<CreditAccount> getAccount();
  Future<List<CreditTransaction>> getTransactions();
  Future<CreditPaymentResult> makePayment({
    required num amount,
    required String method,
  });
}
