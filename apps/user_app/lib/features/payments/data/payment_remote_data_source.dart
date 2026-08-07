import 'package:dio/dio.dart';

import '../../../app/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import 'payment_models.dart';

/// Backend payments API: `POST /payments` (order payments) and
/// `POST /credit/repay` (credit repayment). Both return the Razorpay order the
/// client SDK settles against.
class PaymentRemoteDataSource {
  PaymentRemoteDataSource(this._client);

  final ApiClient _client;

  Map<String, dynamic> _obj(dynamic raw) {
    final data = raw is Map && raw['data'] is Map ? raw['data'] : raw;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  num _num(dynamic v) => v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;

  RazorpayOrder _toOrder(Map<String, dynamic> j) => RazorpayOrder(
        paymentId: (j['id'] ?? '').toString(),
        keyId: (j['keyId'] ?? '').toString(),
        currency: (j['currency'] ?? 'INR').toString(),
        gatewayOrderId: (j['gatewayOrderId'] ?? '').toString(),
        amount: _num(j['amount']),
        status: (j['status'] ?? '').toString(),
      );

  /// Builds the Idempotency-Key header. Prefer a caller-supplied [key] that is
  /// stable across retries of the SAME logical payment — a fresh timestamp per
  /// call would defeat idempotency (a timed-out retry would create a second
  /// charge/order). Falls back to a generated key only when no key is passed.
  Options _idem(String prefix, [String? key]) => Options(
        headers: {
          'Idempotency-Key':
              key ?? '${prefix}_${DateTime.now().microsecondsSinceEpoch}',
        },
      );

  /// Initiates payment for a placed order.
  Future<RazorpayOrder> startOrderPayment({
    required String orderId,
    required num amount,
    required String method,
    String? idempotencyKey,
  }) async {
    final res = await _client.post<dynamic>(
      ApiConstants.payments,
      data: {
        'purpose': 'order',
        'order_id': orderId,
        'amount': amount,
        'method': method,
      },
      options: _idem('pay', idempotencyKey),
    );
    return _toOrder(_obj(res.data));
  }

  /// Hands the Razorpay Checkout success triple to the backend, which re-computes
  /// the HMAC over `order_id|payment_id` and settles the payment.
  ///
  /// This is what makes a payment real to the server. Without it the app showed a
  /// success screen purely on the client SDK's callback and the backend never
  /// learned the money had arrived.
  Future<RazorpayOrder> confirmPayment({
    required String paymentId,
    required String gatewayOrderId,
    required String gatewayPaymentId,
    required String signature,
  }) async {
    final res = await _client.post<dynamic>(
      '${ApiConstants.payments}/$paymentId/confirm',
      data: {
        'razorpay_order_id': gatewayOrderId,
        'razorpay_payment_id': gatewayPaymentId,
        'razorpay_signature': signature,
      },
    );
    return _toOrder(_obj(res.data));
  }

  /// Initiates a credit repayment.
  Future<RazorpayOrder> startRepayment({
    required num amount,
    required String method,
    String? statementId,
    String? idempotencyKey,
  }) async {
    final res = await _client.post<dynamic>(
      ApiConstants.creditRepay,
      data: {
        'amount': amount,
        'method': method,
        if (statementId != null && statementId.isNotEmpty) 'statement_id': statementId,
      },
      options: _idem('repay', idempotencyKey),
    );
    return _toOrder(_obj(res.data));
  }
}
