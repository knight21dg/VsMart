import 'package:equatable/equatable.dart';

/// One billing cycle (weekly or monthly) with its opening/closing balances and
/// movement. Statements are generated per cycle.
class BillingCycle extends Equatable {
  const BillingCycle({
    required this.cycleId,
    required this.startDate,
    required this.endDate,
    required this.dueDate,
    required this.openingBalance,
    required this.newPurchases,
    required this.paymentsReceived,
    required this.closingBalance,
    this.penalties = 0,
  });

  final String cycleId;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime dueDate;
  final num openingBalance;
  final num newPurchases;
  final num paymentsReceived;
  final num penalties;
  final num closingBalance;

  bool get isCurrent {
    final now = DateTime.now();
    return !now.isBefore(startDate) && !now.isAfter(endDate);
  }

  @override
  List<Object?> get props => [
        cycleId,
        startDate,
        endDate,
        dueDate,
        openingBalance,
        newPurchases,
        paymentsReceived,
        penalties,
        closingBalance,
      ];
}
