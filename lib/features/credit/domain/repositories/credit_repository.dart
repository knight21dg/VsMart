import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/credit_account.dart';
import '../entities/credit_payment_result.dart';
import '../entities/credit_transaction.dart';

/// Credit account, ledger and repayment operations.
abstract interface class CreditRepository {
  /// The customer's current credit standing.
  Future<Either<Failure, CreditAccount>> getAccount();

  /// The credit ledger (purchases and payments), most recent first.
  Future<Either<Failure, List<CreditTransaction>>> getTransactions();

  /// Make a repayment of [amount] via [method]; returns the receipt and the
  /// refreshed account.
  Future<Either<Failure, CreditPaymentResult>> makePayment({
    required num amount,
    required String method,
  });
}
