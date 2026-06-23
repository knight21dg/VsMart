import 'package:dartz/dartz.dart';

import '../../../../app/constants/storage_keys.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/network/base_repository.dart';
import '../../../../core/network/network_info.dart';
import '../../../../core/storage/hive_service.dart';
import '../../domain/entities/billing_cycle.dart';
import '../../domain/entities/billing_enums.dart';
import '../../domain/entities/collection_record.dart';
import '../../domain/entities/credit_ledger_entry.dart';
import '../../domain/entities/invoice.dart';
import '../../domain/entities/repayment.dart';
import '../../domain/entities/statement.dart';
import '../../domain/repositories/billing_repository.dart';
import '../datasources/billing_data_source.dart';
import '../models/billing_models.dart';

/// [BillingRepository] — ledger + payment history persist to Hive (offline-
/// first); cycles/statements/invoices come from the data source.
class BillingRepositoryImpl with BaseRepository implements BillingRepository {
  BillingRepositoryImpl({
    required this.dataSource,
    required this.hive,
    required this.networkInfo,
  });

  final BillingDataSource dataSource;
  final HiveService hive;

  @override
  final NetworkInfo networkInfo;

  static const _key = 'entries';

  List<CreditLedgerEntry> _readLedger() {
    final raw = hive.box(StorageKeys.creditLedgerBox).get(_key);
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => CreditLedgerEntryModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return [];
  }

  Future<void> _saveLedger(List<CreditLedgerEntry> entries) => hive
      .box(StorageKeys.creditLedgerBox)
      .put(_key, entries.map(CreditLedgerEntryModel.toJson).toList());

  List<Repayment> _readHistory() {
    final raw = hive.box(StorageKeys.paymentHistoryBox).get(_key);
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => RepaymentModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return [];
  }

  Future<void> _saveHistory(List<Repayment> items) => hive
      .box(StorageKeys.paymentHistoryBox)
      .put(_key, items.map(RepaymentModel.toJson).toList());

  List<CollectionRecord> _readCollections() {
    final raw = hive.box(StorageKeys.collectionBox).get(_key);
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => CollectionRecordModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return [];
  }

  Future<void> _saveCollections(List<CollectionRecord> items) => hive
      .box(StorageKeys.collectionBox)
      .put(_key, items.map(CollectionRecordModel.toJson).toList());

  @override
  Future<Either<Failure, num>> getCreditLimit() =>
      guard(dataSource.getCreditLimit, requireConnection: false);

  @override
  Future<Either<Failure, List<CreditLedgerEntry>>> getLedger() =>
      guard(() async {
        var ledger = _readLedger();
        if (ledger.isEmpty) {
          ledger = await dataSource.getLedger();
          await _saveLedger(ledger);
        }
        return ledger;
      }, requireConnection: false);

  @override
  Future<Either<Failure, List<BillingCycle>>> getCycles() =>
      guard(dataSource.getCycles, requireConnection: false);

  @override
  Future<Either<Failure, List<Statement>>> getStatements() =>
      guard(dataSource.getStatements, requireConnection: false);

  @override
  Future<Either<Failure, Statement?>> getCurrentStatement() =>
      guard(() async {
        final statements = await dataSource.getStatements();
        return statements.isEmpty ? null : statements.first;
      }, requireConnection: false);

  @override
  Future<Either<Failure, List<Invoice>>> getInvoices() =>
      guard(dataSource.getInvoices, requireConnection: false);

  @override
  Future<Either<Failure, List<Repayment>>> getPaymentHistory() =>
      guard(() async {
        var history = _readHistory();
        if (history.isEmpty) {
          history = await dataSource.getPaymentHistory();
          await _saveHistory(history);
        }
        return history;
      }, requireConnection: false);

  @override
  Future<Either<Failure, Repayment>> makeRepayment({
    required num amount,
    required RepaymentMethod method,
    String? statementId,
  }) =>
      guard(() async {
        // Records the repayment on the server (append-only credit ledger).
        final repayment = await dataSource.makeRepayment(
          amount: amount,
          method: method,
          statementId: statementId,
        );
        // Invalidate cached ledger + history so the next read reflects the
        // server's authoritative state instead of a stale snapshot.
        await hive.box(StorageKeys.creditLedgerBox).delete(_key);
        await hive.box(StorageKeys.paymentHistoryBox).delete(_key);
        return repayment;
      }, requireConnection: true);

  @override
  Future<Either<Failure, List<CollectionRecord>>> getCollections() =>
      guard(() async {
        var records = _readCollections();
        if (records.isEmpty) {
          records = await dataSource.getCollections();
          await _saveCollections(records);
        }
        return records;
      }, requireConnection: false);

  @override
  Future<Either<Failure, CollectionRecord>> requestCollection({
    required num amount,
    String? address,
  }) =>
      guard(() async {
        // Creates the collection request on the server.
        final record = await dataSource.requestCollection(amount: amount);
        // Drop the cached list so the next read re-fetches from the backend.
        await hive.box(StorageKeys.collectionBox).delete(_key);
        return record;
      }, requireConnection: true);
}
