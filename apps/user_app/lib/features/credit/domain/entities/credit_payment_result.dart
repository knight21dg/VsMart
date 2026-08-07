import 'package:equatable/equatable.dart';

import 'credit_account.dart';

/// Outcome of a credit repayment: the receipt details plus the refreshed
/// account standing and any VS-score reward.
class CreditPaymentResult extends Equatable {
  const CreditPaymentResult({
    required this.transactionId,
    required this.amountPaid,
    required this.method,
    required this.account,
    this.scorePointsEarned = 0,
  });

  final String transactionId;
  final num amountPaid;
  final String method;
  final CreditAccount account;
  final int scorePointsEarned;

  @override
  List<Object?> get props =>
      [transactionId, amountPaid, method, account, scorePointsEarned];
}
