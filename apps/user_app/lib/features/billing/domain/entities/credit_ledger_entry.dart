import 'package:equatable/equatable.dart';

import 'billing_enums.dart';

/// A single line in the customer's credit ledger — the atomic unit of the
/// billing system. Purchases/penalties are debits; repayments/refunds are
/// credits. `balanceAfter` is the running outstanding balance after this entry.
class CreditLedgerEntry extends Equatable {
  const CreditLedgerEntry({
    required this.id,
    required this.type,
    required this.status,
    required this.amount,
    required this.date,
    required this.description,
    this.balanceAfter,
    this.orderId,
    this.cycleId,
  });

  final String id;
  final TransactionType type;
  final TransactionStatus status;
  final num amount;
  final DateTime date;
  final String description;
  final num? balanceAfter;
  final String? orderId;
  final String? cycleId;

  /// Signed effect on the outstanding balance (+debit / −credit).
  num get signedAmount => type.isDebit ? amount : -amount;

  bool get isSettled => status == TransactionStatus.completed;

  @override
  List<Object?> get props =>
      [id, type, status, amount, date, description, balanceAfter, orderId, cycleId];
}
