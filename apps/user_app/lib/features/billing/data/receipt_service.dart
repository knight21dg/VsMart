import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/providers/core_providers.dart';

/// Fetches the branded payment-receipt PDF (`GET /payments/<id>/receipt`).
///
/// Order invoices already had this; credit repayments did not — "Download
/// Receipt" only showed a snackbar, so a customer who repaid their credit line
/// had no proof of payment at all.
class ReceiptService {
  ReceiptService(this._client);

  final ApiClient _client;

  Future<Uint8List> fetch(String paymentId) async {
    final res = await _client.get<List<int>>(
      ApiConstants.paymentReceipt(paymentId),
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data ?? const <int>[]);
  }

  /// The credit statement PDF (`GET /credit/statements/<id>/pdf`). Backs the
  /// statement-detail Download button, which used to fake a "downloaded" snackbar.
  Future<Uint8List> fetchStatement(String statementId) async {
    final res = await _client.get<List<int>>(
      ApiConstants.creditStatementPdf(statementId),
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data ?? const <int>[]);
  }
}

final receiptServiceProvider = Provider<ReceiptService>(
  (ref) => ReceiptService(ref.watch(apiClientProvider)),
);
