/// A payment initiated on the backend (`POST /payments` / `POST /credit/repay`),
/// carrying everything the Razorpay client SDK needs. In mock mode (no real
/// Razorpay key configured) the backend auto-settles and [status] is already
/// `success`, so no checkout sheet is opened.
class RazorpayOrder {
  const RazorpayOrder({
    required this.paymentId,
    required this.keyId,
    required this.currency,
    required this.gatewayOrderId,
    required this.amount,
    required this.status,
  });

  /// Backend Payment id.
  final String paymentId;

  /// Razorpay public key id (or `rzp_test_mock` when no live key is set).
  final String keyId;
  final String currency;

  /// Razorpay order id to settle against.
  final String gatewayOrderId;

  /// Amount in rupees.
  final num amount;

  /// Backend payment status (`success` once settled).
  final String status;

  static const _mockKey = 'rzp_test_mock';

  /// Already settled server-side (mock gateway in dev/test).
  bool get isSettled => status == 'success';

  /// A live gateway is configured and the payment still needs the sheet.
  bool get needsGateway =>
      !isSettled && keyId.isNotEmpty && keyId != _mockKey && gatewayOrderId.isNotEmpty;
}

/// Result of attempting to settle a payment.
class PaymentOutcome {
  const PaymentOutcome({
    required this.success,
    this.paymentId,
    this.gatewayPaymentId,
    this.gatewayOrderId,
    this.signature,
    this.message,
  });

  final bool success;

  /// Backend Payment id (the server record).
  final String? paymentId;

  /// Razorpay gateway payment id (when the sheet was used).
  final String? gatewayPaymentId;

  /// The Razorpay order id the sheet settled against.
  final String? gatewayOrderId;

  /// HMAC of `order_id|payment_id` signed with our API secret. Only the server
  /// can validate it, which is what turns the SDK's client-side "success" into
  /// something trustworthy — so it must be forwarded, not discarded.
  final String? signature;
  final String? message;

  /// Whether this outcome carries everything `POST /payments/<id>/confirm` needs.
  bool get isVerifiable =>
      (gatewayOrderId?.isNotEmpty ?? false) &&
      (gatewayPaymentId?.isNotEmpty ?? false) &&
      (signature?.isNotEmpty ?? false);
}
