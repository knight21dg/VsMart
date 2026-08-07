import 'package:equatable/equatable.dart';

import 'billing_enums.dart';

/// A repayment against the outstanding credit balance. Doubles as a payment
/// history record.
class Repayment extends Equatable {
  const Repayment({
    required this.id,
    required this.amount,
    required this.method,
    required this.status,
    required this.date,
    this.reference,
    this.statementId,
  });

  final String id;
  final num amount;
  final RepaymentMethod method;
  final TransactionStatus status;
  final DateTime date;
  final String? reference;
  final String? statementId;

  bool get isSuccessful => status == TransactionStatus.completed;

  @override
  List<Object?> get props =>
      [id, amount, method, status, date, reference, statementId];
}
