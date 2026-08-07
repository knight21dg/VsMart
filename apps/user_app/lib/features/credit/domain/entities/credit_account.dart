import 'package:equatable/equatable.dart';

/// Billing cadence for a customer's credit line.
enum BillingCycle { weekly, monthly }

/// Standing of the credit line itself.
enum CreditAccountStatus { active, frozen, closed }

/// A customer's credit standing. Core business rule:
/// `available = creditLimit - outstanding` and orders cannot exceed available.
class CreditAccount extends Equatable {
  const CreditAccount({
    required this.creditLimit,
    required this.outstanding,
    required this.vsScore,
    required this.billingCycle,
    this.status = CreditAccountStatus.active,
    this.dueDate,
    this.nextDueAmount = 0,
    this.purchasesThisMonth = 0,
    this.paymentsThisMonth = 0,
    this.lenderName,
    this.loanAccountNumber,
    this.interestRate,
    this.sanctionedLimit,
  });

  final num creditLimit;
  final num outstanding;
  final int vsScore;
  final BillingCycle billingCycle;
  final CreditAccountStatus status;
  final DateTime? dueDate;

  /// Amount due on [dueDate] (the minimum/statement due, not the full outstanding).
  final num nextDueAmount;
  final num purchasesThisMonth;
  final num paymentsThisMonth;

  // ── Lending-partner (NBFC/LSP) disclosure — null until a partner is configured.
  final String? lenderName;
  final String? loanAccountNumber;
  final num? interestRate;
  final num? sanctionedLimit;

  /// Spend headroom remaining on the credit line.
  num get available {
    final a = creditLimit - outstanding;
    return a < 0 ? 0 : a;
  }

  /// Fraction of the limit currently used (0..1).
  double get utilization {
    if (creditLimit <= 0) return 0;
    return (outstanding / creditLimit).clamp(0, 1).toDouble();
  }

  bool get hasOutstanding => outstanding > 0;
  bool get isActive => status == CreditAccountStatus.active;
  bool get isFrozen => status == CreditAccountStatus.frozen;
  bool get isClosed => status == CreditAccountStatus.closed;

  /// True when a regulated lending partner backs this credit line.
  bool get hasLendingPartner => (lenderName ?? '').trim().isNotEmpty;

  /// Whole days until [dueDate] relative to [now] (0 if no due date).
  int daysUntilDue(DateTime now) {
    final due = dueDate;
    if (due == null) return 0;
    return due.difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  CreditAccount copyWith({num? outstanding, int? vsScore, num? paymentsThisMonth}) {
    return CreditAccount(
      creditLimit: creditLimit,
      outstanding: outstanding ?? this.outstanding,
      vsScore: vsScore ?? this.vsScore,
      billingCycle: billingCycle,
      status: status,
      dueDate: dueDate,
      nextDueAmount: nextDueAmount,
      purchasesThisMonth: purchasesThisMonth,
      paymentsThisMonth: paymentsThisMonth ?? this.paymentsThisMonth,
      lenderName: lenderName,
      loanAccountNumber: loanAccountNumber,
      interestRate: interestRate,
      sanctionedLimit: sanctionedLimit,
    );
  }

  @override
  List<Object?> get props => [
        creditLimit,
        outstanding,
        vsScore,
        billingCycle,
        status,
        dueDate,
        nextDueAmount,
        purchasesThisMonth,
        paymentsThisMonth,
        lenderName,
        loanAccountNumber,
        interestRate,
        sanctionedLimit,
      ];
}
