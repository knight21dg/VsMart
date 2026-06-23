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

  Options _idem(String prefix) => Options(
        headers: {'Idempotency-Key': '${prefix}_${DateTime.now().microsecondsSinceEpoch}'},
      );

  /// Initiates payment for a placed order.
  Future<RazorpayOrder> startOrderPayment({
    required String orderId,
    required num amount,
    required String method,
  }) async {
    final res = await _client.post<dynamic>(
      ApiConstants.payments,
      data: {
        'purpose': 'order',
        'order_id': orderId,
        'amount': amount,
        'method': method,
      },
      options: _idem('pay'),
    );
    return _toOrder(_obj(res.data));
  }

  /// Initiates a credit repayment.
  Future<RazorpayOrder> startRepayment({
    required num amount,
    required String method,
    String? statementId,
  }) async {
    final res = await _client.post<dynamic>(
      ApiConstants.creditRepay,
      data: {
        'amount': amount,
        'method': method,
        if (statementId != null && statementId.isNotEmpty) 'statement_id': statementId,
      },
      options: _idem('repay'),
    );
    return _toOrder(_obj(res.data));
  }
}
