import '../entities/credit_ledger_entry.dart';
import '../entities/statement.dart';

/// Derives all credit figures from the ledger — the single calculation
/// authority for the dashboard, statements, and repayment flows.
class CreditCalculationService {
  const CreditCalculationService();

  /// Outstanding balance = sum of settled signed entries (clamped at 0).
  num outstandingBalance(List<CreditLedgerEntry> ledger) {
    final balance = ledger
        .where((e) => e.isSettled)
        .fold<num>(0, (sum, e) => sum + e.signedAmount);
    return balance < 0 ? 0 : balance;
  }

  num availableCredit(num creditLimit, List<CreditLedgerEntry> ledger) {
    final available = creditLimit - outstandingBalance(ledger);
    return available < 0 ? 0 : available;
  }

  /// Utilization 0..1.
  double utilizationPercentage(num creditLimit, List<CreditLedgerEntry> ledger) {
    if (creditLimit <= 0) return 0;
    return (outstandingBalance(ledger) / creditLimit).clamp(0, 1).toDouble();
  }

  /// Minimum due = max(10% of amount due, ₹100), capped at the amount due.
  num minimumDue(Statement? statement) {
    if (statement == null) return 0;
    final due = statement.amountDue;
    if (due <= 0) return 0;
    final tenPercent = due * 0.10;
    final floor = due < 100 ? due : 100;
    final minimum = tenPercent > floor ? tenPercent : floor;
    return minimum > due ? due : minimum;
  }

  DateTime? nextDueDate(Statement? statement) => statement?.dueDate;

  /// Late fee accrues ₹[feePerWeek] per started week past the due date.
  num lateFees(Statement? statement, {num feePerWeek = 50}) {
    if (statement == null || !statement.isOverdue) return 0;
    final daysLate = DateTime.now().difference(statement.dueDate).inDays;
    if (daysLate <= 0) return 0;
    final weeks = (daysLate / 7).ceil();
    return weeks * feePerWeek;
  }
}
