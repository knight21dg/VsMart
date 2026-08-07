import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';

import '../../../app/constants/api_constants.dart';
import '../../../core/network/api_client.dart';

/// One photo the customer attaches to a return, already read into memory.
class ReturnPhotoUpload {
  const ReturnPhotoUpload({required this.bytes, required this.filename});

  final List<int> bytes;
  final String filename;
}

/// A single line within a return request.
class ReturnItem extends Equatable {
  const ReturnItem({
    required this.productName,
    required this.quantity,
    required this.amount,
  });

  final String productName;
  final int quantity;
  final num amount;

  @override
  List<Object?> get props => [productName, quantity, amount];
}

/// A customer return / refund request, from `GET /returns`.
class ReturnRequest extends Equatable {
  const ReturnRequest({
    required this.id,
    required this.orderCode,
    required this.reason,
    required this.status,
    this.description,
    this.refundAmount = 0,
    required this.createdAt,
    this.resolvedAt,
    this.items = const [],
  });

  final String id;
  final String orderCode;
  final String reason;
  final String status;
  final String? description;

  /// Amount refunded (₹) once the return is settled.
  final num refundAmount;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final List<ReturnItem> items;

  @override
  List<Object?> get props => [
        id,
        orderCode,
        reason,
        status,
        description,
        refundAmount,
        createdAt,
        resolvedAt,
        items,
      ];
}

/// Backend returns API: `/returns`, `/orders/{code}/returns`, `/returns/{code}`.
class ReturnsRemoteDataSource {
  ReturnsRemoteDataSource(this._client);

  final ApiClient _client;

  List<Map<String, dynamic>> _list(dynamic raw) {
    final data = raw is Map ? raw['data'] : raw;
    final list = data is List ? data : const [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Map<String, dynamic> _obj(dynamic raw) {
    final data = raw is Map && raw['data'] is Map ? raw['data'] : raw;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  num _num(dynamic v) => v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;

  DateTime _date(dynamic v) =>
      DateTime.tryParse(v?.toString() ?? '')?.toLocal() ?? DateTime.now();

  DateTime? _dateOrNull(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  Future<List<ReturnRequest>> list() async {
    final res = await _client.get<dynamic>(ApiConstants.returns);
    return _list(res.data).map(_toReturn).toList();
  }

  Future<ReturnRequest> detail(String code) async {
    final res = await _client.get<dynamic>(ApiConstants.returnDetail(code));
    return _toReturn(_obj(res.data));
  }

  /// Raises a return against [orderCode].
  ///
  /// [photos] are MANDATORY — the backend rejects a return with no photo
  /// (`RETURN_PHOTOS_REQUIRED`), because they are the evidence the pickup agent
  /// inspects the goods against at the customer's door. They are sent as a
  /// multipart body; `items` travels as a JSON string alongside the files since
  /// multipart carries every field as text.
  ///
  /// The backend also rejects orders that are not yet delivered with a 400
  /// `{success:false, message, error}` body, surfaced here as `(ok:false, …)`.
  Future<({bool ok, String message, ReturnRequest? request})> create({
    required String orderCode,
    required String reason,
    required List<ReturnPhotoUpload> photos,
    String? description,
    List<ReturnItem> items = const [],
  }) async {
    final form = FormData();
    form.fields.add(MapEntry('reason', reason));
    if (description != null && description.isNotEmpty) {
      form.fields.add(MapEntry('description', description));
    }
    if (items.isNotEmpty) {
      form.fields.add(MapEntry(
        'items',
        jsonEncode([
          for (final i in items)
            {
              'productName': i.productName,
              'quantity': i.quantity,
              'amount': i.amount,
            },
        ]),
      ));
    }
    for (final photo in photos) {
      form.files.add(MapEntry(
        'photos',
        MultipartFile.fromBytes(photo.bytes, filename: photo.filename),
      ));
    }

    final res = await _client.post<dynamic>(
      ApiConstants.orderReturns(orderCode),
      data: form,
    );
    final body = res.data;
    if (body is Map && body['success'] == false) {
      return (
        ok: false,
        message: (body['message'] ??
                body['error']?['message'] ??
                'Could not request a return')
            .toString(),
        request: null,
      );
    }
    // The success envelope carries the dispatch outcome: a pickup partner was
    // either assigned right away or the store will assign one shortly.
    final message = body is Map && body['message'] != null
        ? body['message'].toString()
        : 'Return request submitted';
    return (ok: true, message: message, request: _toReturn(_obj(body)));
  }

  ReturnRequest _toReturn(Map<String, dynamic> j) => ReturnRequest(
        id: (j['id'] ?? '').toString(),
        orderCode: (j['orderCode'] ?? '').toString(),
        reason: (j['reason'] ?? '').toString(),
        status: (j['status'] ?? 'requested').toString(),
        description: j['description'] as String?,
        refundAmount: _num(j['refundAmount']),
        createdAt: _date(j['createdAt']),
        resolvedAt: _dateOrNull(j['resolvedAt']),
        items: ((j['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => ReturnItem(
                  productName: (m['productName'] ?? '').toString(),
                  quantity: (m['quantity'] as num?)?.toInt() ?? 0,
                  amount: _num(m['amount']),
                ))
            .toList(),
      );
}
