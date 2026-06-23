import 'dart:async';

import 'package:razorpay_flutter/razorpay_flutter.dart';

import 'payment_models.dart';

/// Thin wrapper around the Razorpay checkout sheet that exposes a Future-based
/// API (the plugin is event-driven). One [Razorpay] instance per transaction.
class RazorpayCheckoutService {
  Future<PaymentOutcome> open(
    RazorpayOrder order, {
    required String phone,
    String? email,
    String name = 'VS Mart',
  }) {
    final razorpay = Razorpay();
    final completer = Completer<PaymentOutcome>();

    void finish(PaymentOutcome outcome) {
      if (!completer.isCompleted) completer.complete(outcome);
    }

    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
      finish(PaymentOutcome(success: true, gatewayPaymentId: r.paymentId));
    });
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      finish(PaymentOutcome(
        success: false,
        message: (r.message?.isNotEmpty ?? false)
            ? r.message
            : 'Payment was not completed.',
      ));
    });
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse r) {
      // Wallet selection still resolves via SUCCESS/ERROR; nothing to do here.
    });

    try {
      razorpay.open({
        'key': order.keyId,
        'order_id': order.gatewayOrderId,
        'amount': (order.amount * 100).round(), // paise
        'currency': order.currency,
        'name': name,
        'prefill': {
          'contact': phone,
          if (email != null && email.isNotEmpty) 'email': email,
        },
        'theme': {'color': '#0F9D58'},
      });
    } catch (e) {
      finish(PaymentOutcome(success: false, message: e.toString()));
    }

    return completer.future.whenComplete(() {
      // Defer disposal so the plugin finishes dispatching its callback.
      Future<void>.delayed(const Duration(milliseconds: 1500), razorpay.clear);
    });
  }
}
