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
  }) async {
    final order = await _remote.startOrderPayment(
      orderId: orderId,
      amount: amount,
      method: method,
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
  }) async {
    final order = await _remote.startRepayment(
      amount: amount,
      method: method,
      statementId: statementId,
    );
    return _settle(order, phone, email);
  }
}
