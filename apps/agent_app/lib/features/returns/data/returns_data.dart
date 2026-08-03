import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';

import '../../../core/api.dart';
import '../../../core/api_exception.dart';

// ── parse helpers (null-safe across num / String / null) ──
num _num(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? 0;
  return 0;
}

int _int(dynamic v) => _num(v).toInt();

double _double(dynamic v) => _num(v).toDouble();

double? _doubleOrNull(dynamic v) =>
    v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

String _str(dynamic v) => v == null ? '' : v.toString();

/// Reason codes accepted by POST /agent/return-pickups/{id}/reject and
/// /reschedule. Mirrors returns.models.ReturnPickupTask.ReasonCode.
enum ReturnRejectReason {
  itemUsed('item_used', 'Item has been used'),
  itemDamagedByCustomer(
      'item_damaged_by_customer', 'Damaged by the customer'),
  wrongItem('wrong_item', 'Wrong item offered'),
  quantityMismatch('quantity_mismatch', 'Quantity does not match'),
  packagingMissing('packaging_missing', 'Original packaging missing'),
  other('other', 'Other reason');

  const ReturnRejectReason(this.code, this.label);
  final String code;
  final String label;
}

enum ReturnRescheduleReason {
  customerUnavailable('customer_unavailable', 'Customer not available'),
  customerCancelled('customer_cancelled', 'Customer wants to cancel'),
  other('other', 'Other reason');

  const ReturnRescheduleReason(this.code, this.label);
  final String code;
  final String label;
}

/// One line the customer asked to return, with the agent's accept decision.
class ReturnLine extends Equatable {
  const ReturnLine({
    required this.id,
    required this.productName,
    required this.quantity,
    required this.amount,
    required this.acceptedQuantity,
  });

  final String id;
  final String productName;
  final int quantity;
  final double amount;

  /// Null until the agent decides — the full [quantity] is implied.
  final int? acceptedQuantity;

  int get settledQuantity => acceptedQuantity ?? quantity;

  double get unitPrice => quantity == 0 ? 0 : amount / quantity;

  factory ReturnLine.fromMap(Map<String, dynamic> m) => ReturnLine(
        id: _str(m['id']),
        productName: _str(m['productName'] ?? m['product_name']),
        quantity: _int(m['quantity']),
        amount: _double(m['amount']),
        acceptedQuantity: m['acceptedQuantity'] ?? m['accepted_quantity'] == null
            ? null
            : _int(m['acceptedQuantity'] ?? m['accepted_quantity']),
      );

  @override
  List<Object?> get props => [id, productName, quantity, amount, acceptedQuantity];
}

/// A customer- or agent-supplied photo backing the return.
class ReturnPhoto extends Equatable {
  const ReturnPhoto({required this.id, required this.source});

  final String id;

  /// `customer` (submitted with the request) or `agent` (captured at the door).
  final String source;

  bool get isCustomer => source == 'customer';

  /// Permission-gated stream URL, relative to /api/v1.
  String get path => '/returns/photos/$id';

  factory ReturnPhoto.fromMap(Map<String, dynamic> m) =>
      ReturnPhoto(id: _str(m['id']), source: _str(m['source']));

  @override
  List<Object?> get props => [id, source];
}

/// A doorstep return-pickup task assigned to the agent.
///
/// Statuses, in order:
///   assigned → accepted → en_route → reached
///   → completed (goods collected) | rejected (refused at the door)
/// plus `rescheduled`, which stays OPEN for another attempt.
class ReturnPickup extends Equatable {
  const ReturnPickup({
    required this.id,
    required this.status,
    required this.attemptNo,
    required this.returnCode,
    required this.orderCode,
    required this.reason,
    required this.description,
    required this.refundAmount,
    required this.reasonCode,
    required this.note,
    required this.customerName,
    required this.customerPhone,
    required this.address,
    required this.items,
    required this.photos,
    this.destLat,
    this.destLng,
    required this.assignedAt,
    required this.reachedAt,
    required this.completedAt,
  });

  final String id;
  final String status;
  final int attemptNo;

  /// The customer-facing return code (e.g. RET1042).
  final String returnCode;
  final String orderCode;

  /// Why the customer says they're returning it.
  final String reason;
  final String description;

  /// What the customer expects back — recalculated on a partial accept.
  final double refundAmount;

  /// Set once the agent rejects or reschedules.
  final String reasonCode;
  final String note;

  final String customerName;
  final String customerPhone;
  final String address;
  final List<ReturnLine> items;
  final List<ReturnPhoto> photos;
  final double? destLat;
  final double? destLng;

  final String assignedAt;
  final String reachedAt;
  final String completedAt;

  bool get hasLocation => destLat != null && destLng != null;

  List<ReturnPhoto> get customerPhotos =>
      photos.where((p) => p.isCustomer).toList();

  List<ReturnPhoto> get agentPhotos =>
      photos.where((p) => !p.isCustomer).toList();

  /// The agent must capture their own condition photo before completing.
  bool get hasAgentPhoto => agentPhotos.isNotEmpty;

  bool get isAtDoor => status == 'reached';

  bool get isTerminal => const {
        'completed',
        'rejected',
        'reassigned',
        'cancelled',
      }.contains(status);

  factory ReturnPickup.fromMap(Map<String, dynamic> m) {
    final customer = m['customer'];
    final custMap = customer is Map ? Map<String, dynamic>.from(customer) : null;
    final addr = m['address'];
    final addrMap = addr is Map ? Map<String, dynamic>.from(addr) : null;

    String addressLine() {
      if (addrMap == null) return _str(addr);
      final parts = [
        _str(addrMap['line1'] ?? addrMap['line_1']),
        _str(addrMap['line2'] ?? addrMap['line_2']),
        _str(addrMap['city']),
        _str(addrMap['pincode']),
      ].where((s) => s.isNotEmpty);
      return parts.join(', ');
    }

    List<T> parseList<T>(dynamic raw, T Function(Map<String, dynamic>) build) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => build(Map<String, dynamic>.from(e)))
          .toList();
    }

    return ReturnPickup(
      id: _str(m['id']),
      status: _str(m['status']),
      attemptNo: _int(m['attemptNo'] ?? m['attempt_no']),
      returnCode: _str(m['returnCode'] ?? m['return_code']),
      orderCode: _str(m['orderCode'] ?? m['order_code']),
      reason: _str(m['reason']),
      description: _str(m['description']),
      refundAmount: _double(m['refundAmount'] ?? m['refund_amount']),
      reasonCode: _str(m['reasonCode'] ?? m['reason_code']),
      note: _str(m['note']),
      customerName: _str(custMap?['name']),
      customerPhone: _str(custMap?['phone']),
      address: addressLine(),
      items: parseList(m['items'], ReturnLine.fromMap),
      photos: parseList(m['photos'], ReturnPhoto.fromMap),
      destLat: _doubleOrNull(m['destLat'] ?? m['dest_lat']),
      destLng: _doubleOrNull(m['destLng'] ?? m['dest_lng']),
      assignedAt: _str(m['assignedAt'] ?? m['assigned_at']),
      reachedAt: _str(m['reachedAt'] ?? m['reached_at']),
      completedAt: _str(m['completedAt'] ?? m['completed_at']),
    );
  }

  @override
  List<Object?> get props => [
        id,
        status,
        attemptNo,
        returnCode,
        orderCode,
        refundAmount,
        reasonCode,
        items,
        photos,
      ];
}

/// Return-pickup [ApiException]; parsing + display inherited from the base.
class ReturnApiException extends ApiException {
  ReturnApiException({
    required super.code,
    required super.title,
    required super.message,
    super.nextStep,
    super.statusCode,
  });

  factory ReturnApiException.fromResponse(Response<dynamic>? res) {
    final f = ApiException.parse(res);
    return ReturnApiException(
      code: f.code, title: f.title, message: f.message,
      nextStep: f.nextStep, statusCode: f.statusCode,
    );
  }
}

/// Thin repository over [Api] for the agent return-pickup endpoints.
/// All paths are relative to /api/v1.
class ReturnsRepo {
  ReturnsRepo(this._api);
  final Api _api;

  Response<dynamic> _ensureOk(Response<dynamic> res) {
    if ((res.statusCode ?? 0) >= 400) {
      throw ReturnApiException.fromResponse(res);
    }
    return res;
  }

  ReturnPickup _parse(Response<dynamic> res) =>
      ReturnPickup.fromMap(_api.obj(res.data));

  /// GET /agent/return-pickups → open pickups for the signed-in agent.
  Future<List<ReturnPickup>> assigned() async {
    final res = _ensureOk(await _api.get('/agent/return-pickups'));
    return _api.list(res.data).map(ReturnPickup.fromMap).toList();
  }

  /// GET /agent/return-pickups/history → pickups this agent closed.
  Future<List<ReturnPickup>> history() async {
    final res = _ensureOk(await _api.get('/agent/return-pickups/history'));
    return _api.list(res.data).map(ReturnPickup.fromMap).toList();
  }

  /// GET /agent/return-pickups/{id}
  Future<ReturnPickup> detail(String id) async =>
      _parse(_ensureOk(await _api.get('/agent/return-pickups/$id')));

  /// POST /agent/return-pickups/{id}/accept — take the job.
  Future<ReturnPickup> accept(String id) async =>
      _parse(_ensureOk(await _api.post('/agent/return-pickups/$id/accept')));

  /// POST /agent/return-pickups/{id}/decline — hand the job back to the pool.
  Future<ReturnPickup> decline(String id, String reason) async => _parse(
      _ensureOk(await _api.post('/agent/return-pickups/$id/decline',
          data: {'reason': reason})));

  /// POST /agent/return-pickups/{id}/en-route
  Future<ReturnPickup> enRoute(String id) async =>
      _parse(_ensureOk(await _api.post('/agent/return-pickups/$id/en-route')));

  /// POST /agent/return-pickups/{id}/reach
  Future<ReturnPickup> reach(String id) async =>
      _parse(_ensureOk(await _api.post('/agent/return-pickups/$id/reach')));

  /// POST /agent/return-pickups/{id}/photo — the agent's own condition photo
  /// (multipart). Required before [complete].
  Future<ReturnPickup> uploadPhoto(
    String id,
    List<int> bytes, {
    String filename = 'condition.jpg',
    double? lat,
    double? lng,
  }) async {
    final form = FormData.fromMap({
      'photo': MultipartFile.fromBytes(bytes, filename: filename),
      if (lat != null) 'latitude': lat,
      if (lng != null) 'longitude': lng,
    });
    return _parse(_ensureOk(
        await _api.post('/agent/return-pickups/$id/photo', data: form)));
  }

  /// POST /agent/return-pickups/{id}/complete — accept the goods.
  ///
  /// [decisions] maps line id → accepted quantity for a PARTIAL accept; omit a
  /// line to accept it in full.
  /// → 400 RETURN_EVIDENCE_REQUIRED when no agent photo has been captured,
  ///   400 RETURN_QUANTITY_INVALID when a quantity exceeds what was requested,
  ///   409 INVALID_RETURN_TRANSITION before reaching the customer.
  Future<ReturnPickup> complete(
    String id, {
    Map<String, int> decisions = const {},
    String note = '',
  }) async {
    final body = <String, dynamic>{if (note.isNotEmpty) 'note': note};
    if (decisions.isNotEmpty) body['decisions'] = decisions;
    return _parse(_ensureOk(await _api
        .post('/agent/return-pickups/$id/complete', data: body)));
  }

  /// POST /agent/return-pickups/{id}/reject — refuse the goods at the door.
  Future<ReturnPickup> reject(
    String id, {
    required ReturnRejectReason reason,
    String note = '',
  }) async =>
      _parse(_ensureOk(
          await _api.post('/agent/return-pickups/$id/reject', data: {
        'reason_code': reason.code,
        if (note.isNotEmpty) 'note': note,
      })));

  /// POST /agent/return-pickups/{id}/reschedule — defer; stays on the list.
  Future<ReturnPickup> reschedule(
    String id, {
    required ReturnRescheduleReason reason,
    String note = '',
  }) async =>
      _parse(_ensureOk(
          await _api.post('/agent/return-pickups/$id/reschedule', data: {
        'reason_code': reason.code,
        if (note.isNotEmpty) 'note': note,
      })));
}
