import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../auth/presentation/providers/current_user_provider.dart';
import '../../../payments/presentation/payment_providers.dart';
import '../../data/datasources/billing_backend_data_source.dart';
import '../../data/datasources/billing_data_source.dart';
import '../../data/repositories/billing_repository_impl.dart';
import '../../domain/entities/billing_cycle.dart';
import '../../domain/entities/billing_enums.dart';
import '../../domain/entities/collection_record.dart';
import '../../domain/entities/credit_ledger_entry.dart';
import '../../domain/entities/invoice.dart';
import '../../domain/entities/repayment.dart';
import '../../domain/entities/statement.dart';
import '../../domain/repositories/billing_repository.dart';
import '../../domain/services/credit_calculation_service.dart';

T _unwrap<T>(Either<Failure, T> either) =>
    either.fold((f) => throw f, (value) => value);

/// ---------------------------------------------------------------------------
/// Wiring: data source → repository → calculation service.
/// ---------------------------------------------------------------------------

final billingDataSourceProvider = Provider<BillingDataSource>(
  (ref) => BillingBackendDataSource(ref.watch(apiClientProvider)),
);

final billingRepositoryProvider = Provider<BillingRepository>(
  (ref) => BillingRepositoryImpl(
    dataSource: ref.watch(billingDataSourceProvider),
    hive: ref.watch(hiveServiceProvider),
    networkInfo: ref.watch(networkInfoProvider),
  ),
);

/// The single calculation authority — all credit figures derive from here.
final creditCalculationServiceProvider = Provider<CreditCalculationService>(
  (ref) => const CreditCalculationService(),
);

/// ---------------------------------------------------------------------------
/// Source-of-truth reads (ledger → cycles → statements → invoices → payments).
/// ---------------------------------------------------------------------------

final creditLimitProvider = FutureProvider<num>(
  (ref) async => _unwrap(await ref.watch(billingRepositoryProvider).getCreditLimit()),
);

final creditLedgerProvider = FutureProvider<List<CreditLedgerEntry>>(
  (ref) async => _unwrap(await ref.watch(billingRepositoryProvider).getLedger()),
);

final billingCyclesProvider = FutureProvider<List<BillingCycle>>(
  (ref) async => _unwrap(await ref.watch(billingRepositoryProvider).getCycles()),
);

final statementsProvider = FutureProvider<List<Statement>>(
  (ref) async =>
      _unwrap(await ref.watch(billingRepositoryProvider).getStatements()),
);

final currentStatementProvider = FutureProvider<Statement?>(
  (ref) async =>
      _unwrap(await ref.watch(billingRepositoryProvider).getCurrentStatement()),
);

final invoicesProvider = FutureProvider<List<Invoice>>(
  (ref) async =>
      _unwrap(await ref.watch(billingRepositoryProvider).getInvoices()),
);

final paymentHistoryProvider = FutureProvider<List<Repayment>>(
  (ref) async =>
      _unwrap(await ref.watch(billingRepositoryProvider).getPaymentHistory()),
);

final collectionsProvider = FutureProvider<List<CollectionRecord>>(
  (ref) async =>
      _unwrap(await ref.watch(billingRepositoryProvider).getCollections()),
);

final invoiceByIdProvider = FutureProvider.family<Invoice?, String>(
  (ref, id) async {
    final invoices = await ref.watch(invoicesProvider.future);
    for (final invoice in invoices) {
      if (invoice.invoiceId == id) return invoice;
    }
    return null;
  },
);

final statementByIdProvider = FutureProvider.family<Statement?, String>(
  (ref, id) async {
    final statements = await ref.watch(statementsProvider.future);
    for (final statement in statements) {
      if (statement.statementId == id) return statement;
    }
    return null;
  },
);

/// ---------------------------------------------------------------------------
/// Derived figures — computed by [CreditCalculationService] off the ledger so
/// the dashboard never recomputes balances itself.
/// ---------------------------------------------------------------------------

final outstandingBalanceProvider = FutureProvider<num>((ref) async {
  final ledger = await ref.watch(creditLedgerProvider.future);
  return ref.watch(creditCalculationServiceProvider).outstandingBalance(ledger);
});

final availableCreditProvider = FutureProvider<num>((ref) async {
  final limit = await ref.watch(creditLimitProvider.future);
  final ledger = await ref.watch(creditLedgerProvider.future);
  return ref
      .watch(creditCalculationServiceProvider)
      .availableCredit(limit, ledger);
});

final creditUtilizationProvider = FutureProvider<double>((ref) async {
  final limit = await ref.watch(creditLimitProvider.future);
  final ledger = await ref.watch(creditLedgerProvider.future);
  return ref
      .watch(creditCalculationServiceProvider)
      .utilizationPercentage(limit, ledger);
});

/// Minimum due on the current statement.
final minimumDueProvider = FutureProvider<num>((ref) async {
  final statement = await ref.watch(currentStatementProvider.future);
  return ref.watch(creditCalculationServiceProvider).minimumDue(statement);
});

/// Next payment due date (null when there's no open statement).
final nextDueDateProvider = FutureProvider<DateTime?>((ref) async {
  final statement = await ref.watch(currentStatementProvider.future);
  return ref.watch(creditCalculationServiceProvider).nextDueDate(statement);
});

/// Aggregated, ledger-derived snapshot for the credit dashboard — one await so
/// the screen renders from a single [AsyncValue].
typedef BillingOverview = ({
  num creditLimit,
  num outstanding,
  num available,
  double utilization,
  Statement? currentStatement,
  num minimumDue,
  DateTime? nextDueDate,
  List<CreditLedgerEntry> recentTransactions,
});

final billingOverviewProvider = FutureProvider<BillingOverview>((ref) async {
  final calc = ref.watch(creditCalculationServiceProvider);
  final limit = await ref.watch(creditLimitProvider.future);
  final ledger = await ref.watch(creditLedgerProvider.future);
  final statement = await ref.watch(currentStatementProvider.future);
  return (
    creditLimit: limit,
    outstanding: calc.outstandingBalance(ledger),
    available: calc.availableCredit(limit, ledger),
    utilization: calc.utilizationPercentage(limit, ledger),
    currentStatement: statement,
    minimumDue: calc.minimumDue(statement),
    nextDueDate: calc.nextDueDate(statement),
    recentTransactions: ledger.take(5).toList(),
  );
});

/// ---------------------------------------------------------------------------
/// Write flows — repayment and field collection. Both refresh every ledger-
/// derived provider on success so the dashboard reflects the new balance.
/// ---------------------------------------------------------------------------

/// Holds the most recent successful repayment so the success screen can render
/// it after navigation.
final lastRepaymentProvider = StateProvider<Repayment?>((ref) => null);

void _refreshLedger(Ref ref) {
  ref
    ..invalidate(creditLedgerProvider)
    ..invalidate(paymentHistoryProvider)
    ..invalidate(currentStatementProvider)
    ..invalidate(statementsProvider);
}

/// Drives a repayment; `state` is the in-flight flag. On success it appends to
/// the ledger + payment history, stores the result, and refreshes derived data.
class RepaymentController extends Notifier<bool> {
  @override
  bool build() => false;

  Future<bool> pay({
    required num amount,
    required RepaymentMethod method,
    String? statementId,
  }) async {
    final analytics = ref.read(analyticsServiceProvider);
    analytics.track('payment_started', {
      'amount': amount,
      'method': method.name,
    });
    state = true;
    try {
      final phone = ref.read(currentUserProvider)?.phone ?? '';
      // Records the repayment on the server and settles via Razorpay when a live
      // gateway is configured (auto-settled in mock mode).
      final outcome = await ref.read(paymentServiceProvider).payRepayment(
            amount: amount,
            method: _apiMethod(method),
            statementId: statementId,
            phone: phone,
          );
      state = false;
      if (!outcome.success) {
        analytics.track('payment_failed', {'reason': outcome.message ?? 'cancelled'});
        return false;
      }
      final repayment = Repayment(
        id: outcome.paymentId ?? outcome.gatewayPaymentId ?? '',
        amount: amount,
        method: method,
        status: TransactionStatus.completed,
        date: DateTime.now(),
        statementId: statementId,
      );
      ref.read(lastRepaymentProvider.notifier).state = repayment;
      _refreshLedger(ref);
      analytics
        ..track('payment_completed', {'amount': amount, 'method': method.name})
        ..track('repayment_created', {'id': repayment.id});
      return true;
    } catch (e) {
      state = false;
      analytics.track('payment_failed', {'reason': e.toString()});
      return false;
    }
  }

  /// Maps a [RepaymentMethod] to a backend repay method (upi/card/netbanking).
  String _apiMethod(RepaymentMethod m) => switch (m) {
        RepaymentMethod.card => 'card',
        RepaymentMethod.bankTransfer => 'netbanking',
        _ => 'upi',
      };
}

final repaymentControllerProvider =
    NotifierProvider<RepaymentController, bool>(RepaymentController.new);

/// Drives a cash-collection request (consumed by the Agent App later).
class CollectionController extends Notifier<bool> {
  @override
  bool build() => false;

  Future<CollectionRecord?> request({
    required num amount,
    String? address,
  }) async {
    state = true;
    final result = await ref
        .read(billingRepositoryProvider)
        .requestCollection(amount: amount, address: address);
    state = false;
    return result.fold((_) => null, (record) {
      ref
        ..invalidate(collectionsProvider)
        ..read(analyticsServiceProvider)
            .track('collection_record_created', {'id': record.id});
      return record;
    });
  }
}

final collectionControllerProvider =
    NotifierProvider<CollectionController, bool>(CollectionController.new);
