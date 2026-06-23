import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/billing_cycle.dart';
import '../entities/billing_enums.dart';
import '../entities/collection_record.dart';
import '../entities/credit_ledger_entry.dart';
import '../entities/invoice.dart';
import '../entities/repayment.dart';
import '../entities/statement.dart';

/// The single billing source of truth (ledger → cycles → statements → invoices
/// → payments → collections). Offline-first: the ledger and payment history
/// persist locally; statements/invoices are cached.
abstract interface class BillingRepository {
  Future<Either<Failure, num>> getCreditLimit();
  Future<Either<Failure, List<CreditLedgerEntry>>> getLedger();
  Future<Either<Failure, List<BillingCycle>>> getCycles();
  Future<Either<Failure, List<Statement>>> getStatements();
  Future<Either<Failure, Statement?>> getCurrentStatement();
  Future<Either<Failure, List<Invoice>>> getInvoices();
  Future<Either<Failure, List<Repayment>>> getPaymentHistory();
  Future<Either<Failure, List<CollectionRecord>>> getCollections();

  /// Record a repayment (appends a ledger credit + a payment-history entry).
  Future<Either<Failure, Repayment>> makeRepayment({
    required num amount,
    required RepaymentMethod method,
    String? statementId,
  });

  /// Raise a cash-collection request (consumed by the Agent App later).
  Future<Either<Failure, CollectionRecord>> requestCollection({
    required num amount,
    String? address,
  });
}
