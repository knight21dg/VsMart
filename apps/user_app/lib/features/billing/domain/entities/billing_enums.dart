/// Direction/kind of a credit ledger entry.
enum TransactionType { purchase, repayment, penalty, adjustment, refund }

extension TransactionTypeX on TransactionType {
  String get label => switch (this) {
        TransactionType.purchase => 'Purchase',
        TransactionType.repayment => 'Repayment',
        TransactionType.penalty => 'Penalty',
        TransactionType.adjustment => 'Adjustment',
        TransactionType.refund => 'Refund',
      };

  /// Whether this entry increases the outstanding balance.
  bool get isDebit =>
      this == TransactionType.purchase || this == TransactionType.penalty;

  /// Whether this entry decreases the outstanding balance.
  bool get isCredit => !isDebit;
}

/// Settlement state of a ledger entry.
enum TransactionStatus { pending, completed, failed, reversed }

extension TransactionStatusX on TransactionStatus {
  String get label => switch (this) {
        TransactionStatus.pending => 'Pending',
        TransactionStatus.completed => 'Completed',
        TransactionStatus.failed => 'Failed',
        TransactionStatus.reversed => 'Reversed',
      };
}

/// Lifecycle of an order invoice.
enum InvoiceStatus { pending, paid, overdue, cancelled }

extension InvoiceStatusX on InvoiceStatus {
  String get label => switch (this) {
        InvoiceStatus.pending => 'Pending',
        InvoiceStatus.paid => 'Paid',
        InvoiceStatus.overdue => 'Overdue',
        InvoiceStatus.cancelled => 'Cancelled',
      };
}

/// How a repayment is made.
enum RepaymentMethod { upi, card, bankTransfer, cashCollection }

extension RepaymentMethodX on RepaymentMethod {
  String get label => switch (this) {
        RepaymentMethod.upi => 'UPI',
        RepaymentMethod.card => 'Card',
        RepaymentMethod.bankTransfer => 'Bank Transfer',
        RepaymentMethod.cashCollection => 'Cash Collection',
      };
}

/// Lifecycle of a field-collection record (shared with the Agent App later).
enum CollectionStatus { pending, assigned, collected, failed }

extension CollectionStatusX on CollectionStatus {
  String get label => switch (this) {
        CollectionStatus.pending => 'Pending',
        CollectionStatus.assigned => 'Assigned',
        CollectionStatus.collected => 'Collected',
        CollectionStatus.failed => 'Failed',
      };
}
