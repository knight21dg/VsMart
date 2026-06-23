import 'package:equatable/equatable.dart';

import 'billing_enums.dart';

/// An invoice generated for a credit-funded order.
class Invoice extends Equatable {
  const Invoice({
    required this.invoiceId,
    required this.orderId,
    required this.amount,
    required this.generatedDate,
    required this.status,
  });

  final String invoiceId;
  final String orderId;
  final num amount;
  final DateTime generatedDate;
  final InvoiceStatus status;

  @override
  List<Object?> get props =>
      [invoiceId, orderId, amount, generatedDate, status];
}
