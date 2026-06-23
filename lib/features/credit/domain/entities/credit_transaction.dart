import 'package:equatable/equatable.dart';

/// Kind of a credit-ledger entry. Mirrors the backend ledger `type` values
/// (purchase / repayment / fee / adjustment / refund) so each entry is labelled
/// correctly instead of collapsing to purchase/payment.
enum CreditTransactionType { purchase, payment, fee, adjustment, refund }

/// A single entry in the customer's credit ledger.
class CreditTransaction extends Equatable {
  const CreditTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.date,
    required this.description,
    this.isCredit = false,
    this.balanceAfter,
  });

  final String id;
  final CreditTransactionType type;

  /// Absolute rupee value of the entry.
  final num amount;
  final DateTime date;
  final String description;

  /// True when the entry reduces outstanding (repayment, refund, or a negative
  /// adjustment). Drives the +/- sign and credit/debit colour in the UI.
  final bool isCredit;

  /// Running outstanding balance after this entry, when the backend provides it.
  final num? balanceAfter;

  /// Back-compat alias used by existing widgets.
  bool get isPayment => isCredit;

  @override
  List<Object?> get props => [id, type, amount, date, description, isCredit, balanceAfter];
}
