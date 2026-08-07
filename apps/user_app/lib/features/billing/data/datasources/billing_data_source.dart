import '../../domain/entities/billing_cycle.dart';
import '../../domain/entities/billing_enums.dart';
import '../../domain/entities/collection_record.dart';
import '../../domain/entities/credit_ledger_entry.dart';
import '../../domain/entities/invoice.dart';
import '../../domain/entities/repayment.dart';
import '../../domain/entities/statement.dart';

/// Read/write seam for billing data. Implemented by [BillingBackendDataSource]
/// (the `/credit/*`, `/billing/*`, `/payments/history` and `/collections/history`
/// APIs).
/// Limit + the server-maintained outstanding, together. Read as one unit so the
/// dashboard's core money figures come from the backend authority rather than a
/// client-side sum of a paginated ledger.
typedef CreditSummary = ({num limit, num outstanding});

abstract interface class BillingDataSource {
  /// Authoritative credit summary from `/credit/dashboard`.
  Future<CreditSummary> getCreditSummary();
  Future<List<CreditLedgerEntry>> getLedger();
  Future<List<BillingCycle>> getCycles();
  Future<List<Statement>> getStatements();
  Future<List<Invoice>> getInvoices();
  Future<List<Repayment>> getPaymentHistory();
  Future<List<CollectionRecord>> getCollections();

  /// Records a credit repayment on the server (`POST /credit/repay`).
  Future<Repayment> makeRepayment({
    required num amount,
    required RepaymentMethod method,
    String? statementId,
  });

  /// Requests an at-home cash collection on the server
  /// (`POST /credit/cash-collection`). [idempotencyKey] must be stable across
  /// retries of the same request so a timed-out submit can't create duplicates.
  Future<CollectionRecord> requestCollection({
    required num amount,
    String? idempotencyKey,
  });
}
