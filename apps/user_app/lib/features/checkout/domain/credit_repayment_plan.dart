/// When a VS Credit purchase must be repaid. The customer chooses one at
/// checkout; the backend computes the authoritative due date from the same rule
/// (kept in sync with `orders.services.compute_payout_date`).
enum CreditRepaymentPlan { weekend, monthEnd }

extension CreditRepaymentPlanX on CreditRepaymentPlan {
  /// Wire value sent to the backend (`credit_plan`).
  String get apiValue => switch (this) {
        CreditRepaymentPlan.weekend => 'weekend',
        CreditRepaymentPlan.monthEnd => 'month_end',
      };

  String get label => switch (this) {
        CreditRepaymentPlan.weekend => 'Weekend Payment',
        CreditRepaymentPlan.monthEnd => 'Month-End Payment',
      };

  String get tagline => switch (this) {
        CreditRepaymentPlan.weekend => 'Repay this weekend',
        CreditRepaymentPlan.monthEnd => 'Repay at month end',
      };

  /// The payout (repayment due) date for this plan relative to [from].
  /// - weekend  → the upcoming Sunday (next Sunday if today is Sunday)
  /// - monthEnd → the last calendar day of the current month
  DateTime payoutDate([DateTime? from]) {
    final now = from ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (this) {
      case CreditRepaymentPlan.weekend:
        // DateTime weekday: Mon=1 … Sun=7.
        var days = (DateTime.sunday - today.weekday) % 7;
        if (days == 0) days = 7; // today is Sunday → next Sunday
        return today.add(Duration(days: days));
      case CreditRepaymentPlan.monthEnd:
        // Day 0 of next month == last day of this month.
        return DateTime(today.year, today.month + 1, 0);
    }
  }

  static CreditRepaymentPlan fromApi(String? v) => switch (v) {
        'month_end' => CreditRepaymentPlan.monthEnd,
        _ => CreditRepaymentPlan.weekend,
      };
}
