import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/providers/core_providers.dart';

/// Fetches the branded PDF invoice for an order from the backend
/// (`GET /orders/<code>/invoice`) as raw bytes, ready to preview/print/share.
class InvoiceService {
  InvoiceService(this._client);

  final ApiClient _client;

  Future<Uint8List> fetch(String orderCode) async {
    final res = await _client.get<List<int>>(
      ApiConstants.orderInvoice(orderCode),
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(res.data ?? const <int>[]);
  }
}

final invoiceServiceProvider = Provider<InvoiceService>(
  (ref) => InvoiceService(ref.watch(apiClientProvider)),
);
