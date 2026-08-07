import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/core_providers.dart';
import '../data/payment_models.dart';
import '../data/payment_remote_data_source.dart';
import '../data/razorpay_checkout_service.dart';

final paymentRemoteDataSourceProvider = Provider<PaymentRemoteDataSource>(
  (ref) => PaymentRemoteDataSource(ref.watch(apiClientProvider)),
);

final razorpayCheckoutServiceProvider = Provider<RazorpayCheckoutService>(
  (ref) => RazorpayCheckoutService(),
);

final paymentServiceProvider = Provider<PaymentService>(
  (ref) => PaymentService(
    ref.watch(paymentRemoteDataSourceProvider),
    ref.watch(razorpayCheckoutServiceProvider),
  ),
);

/// Orchestrates a payment: initiate on the backend, then settle via the Razorpay
/// sheet when a live gateway is configured (auto-settled in mock mode).
class PaymentService {
  PaymentService(this._remote, this._checkout);

  final PaymentRemoteDataSource _remote;
  final RazorpayCheckoutService _checkout;

  Future<PaymentOutcome> _settle(RazorpayOrder order, String phone, String? email) async {
    if (order.isSettled) {
      return PaymentOutcome(success: true, paymentId: order.paymentId);
    }
    if (!order.needsGateway) {
      return const PaymentOutcome(
          success: false, message: 'Payment could not be initiated.');
    }
    final r = await _checkout.open(order, phone: phone, email: email);
    if (!r.success) {
      return PaymentOutcome(
        success: false,
        paymentId: order.paymentId,
        message: r.message,
      );
    }
    // The sheet reporting success is a CLIENT claim. Hand the signed triple to
    // the backend, which verifies the HMAC and settles the payment; only then is
    // the money real to the server. Treating the SDK callback alone as success is
    // what let a paid order sit unpaid until the expiry job cancelled it.
    if (r.isVerifiable) {
      try {
        final confirmed = await _remote.confirmPayment(
          paymentId: order.paymentId,
          gatewayOrderId: r.gatewayOrderId!,
          gatewayPaymentId: r.gatewayPaymentId!,
          signature: r.signature!,
        );
        return PaymentOutcome(
          success: confirmed.isSettled,
          paymentId: order.paymentId,
          gatewayPaymentId: r.gatewayPaymentId,
          message: confirmed.isSettled
              ? null
              : 'We\'re still confirming your payment.',
        );
      } catch (_) {
        // The money may well have been taken — say so honestly rather than
        // claiming success, and let the webhook settle it server-side.
        return PaymentOutcome(
          success: false,
          paymentId: order.paymentId,
          gatewayPaymentId: r.gatewayPaymentId,
          message: "We couldn't confirm your payment yet. If money was debited, "
              "it will be reflected shortly — please don't pay again.",
        );
      }
    }
    return PaymentOutcome(
      success: r.success,
      paymentId: order.paymentId,
      gatewayPaymentId: r.gatewayPaymentId,
      message: r.message,
    );
  }

  /// Pays for a placed order. Returns success (incl. mock auto-settle).
  Future<PaymentOutcome> payForOrder({
    required String orderId,
    required num amount,
    required String method,
    required String phone,
    String? email,
    String? idempotencyKey,
  }) async {
    final order = await _remote.startOrderPayment(
      orderId: orderId,
      amount: amount,
      method: method,
      idempotencyKey: idempotencyKey,
    );
    return _settle(order, phone, email);
  }

  /// Settles a credit repayment.
  Future<PaymentOutcome> payRepayment({
    required num amount,
    required String method,
    String? statementId,
    required String phone,
    String? email,
    String? idempotencyKey,
  }) async {
    final order = await _remote.startRepayment(
      amount: amount,
      method: method,
      statementId: statementId,
      idempotencyKey: idempotencyKey,
    );
    return _settle(order, phone, email);
  }
}
