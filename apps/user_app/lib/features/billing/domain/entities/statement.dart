import 'package:equatable/equatable.dart';

import 'credit_ledger_entry.dart';

/// A billing statement for one cycle: the transactions plus the amount due,
/// minimum due, and due date.
class Statement extends Equatable {
  const Statement({
    required this.statementId,
    required this.cycleId,
    required this.generatedDate,
    required this.transactions,
    required this.amountDue,
    required this.minimumDue,
    required this.dueDate,
    this.paid = false,
  });

  final String statementId;
  final String cycleId;
  final DateTime generatedDate;
  final List<CreditLedgerEntry> transactions;
  final num amountDue;
  final num minimumDue;
  final DateTime dueDate;
  final bool paid;

  bool get isOverdue => !paid && DateTime.now().isAfter(dueDate);

  @override
  List<Object?> get props => [
        statementId,
        cycleId,
        generatedDate,
        transactions,
        amountDue,
        minimumDue,
        dueDate,
        paid,
      ];
}
