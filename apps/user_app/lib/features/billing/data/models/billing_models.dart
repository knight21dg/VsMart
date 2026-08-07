import '../../domain/entities/billing_enums.dart';
import '../../domain/entities/collection_record.dart';
import '../../domain/entities/credit_ledger_entry.dart';
import '../../domain/entities/repayment.dart';

T? _byName<T extends Enum>(List<T> values, String? name) {
  if (name == null) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

/// JSON serialization for [CreditLedgerEntry] (Hive `creditLedgerBox`).
abstract final class CreditLedgerEntryModel {
  CreditLedgerEntryModel._();

  static Map<String, dynamic> toJson(CreditLedgerEntry e) => {
        'id': e.id,
        'type': e.type.name,
        'status': e.status.name,
        'amount': e.amount,
        'date': e.date.millisecondsSinceEpoch,
        'description': e.description,
        'balanceAfter': e.balanceAfter,
        'orderId': e.orderId,
        'cycleId': e.cycleId,
      };

  static CreditLedgerEntry fromJson(Map<String, dynamic> j) => CreditLedgerEntry(
        id: j['id'] as String? ?? '',
        type: _byName(TransactionType.values, j['type'] as String?) ??
            TransactionType.purchase,
        status: _byName(TransactionStatus.values, j['status'] as String?) ??
            TransactionStatus.completed,
        amount: (j['amount'] as num?) ?? 0,
        date: DateTime.fromMillisecondsSinceEpoch(
            (j['date'] as num?)?.toInt() ?? 0),
        description: j['description'] as String? ?? '',
        balanceAfter: j['balanceAfter'] as num?,
        orderId: j['orderId'] as String?,
        cycleId: j['cycleId'] as String?,
      );
}

/// JSON serialization for [Repayment] (Hive `paymentHistoryBox`).
abstract final class RepaymentModel {
  RepaymentModel._();

  static Map<String, dynamic> toJson(Repayment r) => {
        'id': r.id,
        'amount': r.amount,
        'method': r.method.name,
        'status': r.status.name,
        'date': r.date.millisecondsSinceEpoch,
        'reference': r.reference,
        'statementId': r.statementId,
      };

  static Repayment fromJson(Map<String, dynamic> j) => Repayment(
        id: j['id'] as String? ?? '',
        amount: (j['amount'] as num?) ?? 0,
        method: _byName(RepaymentMethod.values, j['method'] as String?) ??
            RepaymentMethod.upi,
        status: _byName(TransactionStatus.values, j['status'] as String?) ??
            TransactionStatus.completed,
        date: DateTime.fromMillisecondsSinceEpoch(
            (j['date'] as num?)?.toInt() ?? 0),
        reference: j['reference'] as String?,
        statementId: j['statementId'] as String?,
      );
}

/// JSON serialization for [CollectionRecord] (Hive `collectionBox`). Shared shape
/// with the future Agent App, which will assign agents and flip the status.
abstract final class CollectionRecordModel {
  CollectionRecordModel._();

  static Map<String, dynamic> toJson(CollectionRecord r) => {
        'id': r.id,
        'amount': r.amount,
        'status': r.status.name,
        'createdAt': r.createdAt.millisecondsSinceEpoch,
        'agentId': r.agentId,
        'agentName': r.agentName,
        'collectedAt': r.collectedAt?.millisecondsSinceEpoch,
        'method': r.method.name,
        'address': r.address,
      };

  static CollectionRecord fromJson(Map<String, dynamic> j) => CollectionRecord(
        id: j['id'] as String? ?? '',
        amount: (j['amount'] as num?) ?? 0,
        status: _byName(CollectionStatus.values, j['status'] as String?) ??
            CollectionStatus.pending,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (j['createdAt'] as num?)?.toInt() ?? 0),
        agentId: j['agentId'] as String?,
        agentName: j['agentName'] as String?,
        collectedAt: (j['collectedAt'] as num?) != null
            ? DateTime.fromMillisecondsSinceEpoch(
                (j['collectedAt'] as num).toInt())
            : null,
        method: _byName(RepaymentMethod.values, j['method'] as String?) ??
            RepaymentMethod.cashCollection,
        address: j['address'] as String?,
      );
}
