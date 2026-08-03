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

String _str(dynamic v) => v == null ? '' : v.toString();

bool _bool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }
  return false;
}

double? _doubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

/// Failure reason codes accepted by POST /deliveries/{id}/fail.
enum DeliveryFailReason {
  customerUnreachable('FAILED_CUSTOMER_UNREACHABLE', 'Customer unreachable'),
  addressNotFound('FAILED_ADDRESS_NOT_FOUND', 'Address not found'),
  customerRejected('FAILED_CUSTOMER_REJECTED', 'Customer rejected the order'),
  otpVerification('FAILED_OTP_VERIFICATION', 'OTP verification failed'),
  securityConcern('FAILED_SECURITY_CONCERN', 'Security concern');

  const DeliveryFailReason(this.code, this.label);
  final String code;
  final String label;
}

/// A delivery task assigned to the agent — the production Delivery state
/// machine record (GET /deliveries/assigned, GET /deliveries/{id}).
///
/// Statuses, in order:
///   assigned → accepted → picked_up → out_for_delivery → reached
///   → (otp verified) → (photo captured) → delivered
/// plus the terminal `failed` / `rejected` / `cancelled`.
class AgentDelivery extends Equatable {
  const AgentDelivery({
    required this.id,
    required this.orderCode,
    required this.status,
    required this.attemptNo,
    required this.customerName,
    required this.customerPhone,
    required this.address,
    required this.destLat,
    required this.destLng,
    required this.distanceKm,
    required this.amount,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.itemCount,
    required this.otpVerified,
    required this.manualVerificationRequired,
    required this.failureReason,
    required this.photoKey,
    required this.earnings,
    required this.assignedAt,
    required this.acceptedAt,
    required this.pickedUpAt,
    required this.outForDeliveryAt,
    required this.reachedAt,
    required this.deliveredAt,
  });

  /// Task id — the path segment for every state-machine call.
  final String id;
  final String orderCode;
  final String status;
  final int attemptNo;
  final String customerName;
  final String customerPhone;
  final String address;
  final double? destLat;
  final double? destLng;
  final double distanceKm;
  final double amount;
  final String paymentMethod;
  final String paymentStatus;
  final int itemCount;
  final bool otpVerified;
  final bool manualVerificationRequired;
  final String failureReason;

  /// Proof-of-delivery photo key (set once /photo succeeds).
  final String photoKey;
  final double earnings;
  final String assignedAt;
  final String acceptedAt;
  final String pickedUpAt;
  final String outForDeliveryAt;
  final String reachedAt;
  final String deliveredAt;

  bool get hasPhoto => photoKey.isNotEmpty;

  factory AgentDelivery.fromMap(Map<String, dynamic> m) {
    final customer = m['customer'];
    final custMap = customer is Map ? Map<String, dynamic>.from(customer) : null;

    String fromCustomer(List<String> keys) {
      if (custMap == null) return '';
      for (final k in keys) {
        final v = _str(custMap[k]);
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    return AgentDelivery(
      id: _str(m['id'] ?? m['taskId'] ?? m['task_id']),
      orderCode: _str(m['orderCode'] ?? m['order_code']),
      status: _str(m['status']),
      attemptNo: _int(m['attemptNo'] ?? m['attempt_no']),
      customerName: fromCustomer(['name']),
      customerPhone: fromCustomer(['phone']),
      address: _str(m['address']),
      destLat: _doubleOrNull(m['destLat'] ?? m['dest_lat']),
      destLng: _doubleOrNull(m['destLng'] ?? m['dest_lng']),
      distanceKm: _double(m['distanceKm'] ?? m['distance_km']),
      amount: _double(m['amount']),
      paymentMethod: _str(m['paymentMethod'] ?? m['payment_method']),
      paymentStatus: _str(m['paymentStatus'] ?? m['payment_status']),
      itemCount: _int(m['itemCount'] ?? m['item_count']),
      otpVerified: _bool(m['otpVerified'] ?? m['otp_verified']),
      manualVerificationRequired: _bool(
          m['manualVerificationRequired'] ?? m['manual_verification_required']),
      failureReason: _str(m['failureReason'] ?? m['failure_reason']),
      photoKey: _str(m['photoKey'] ?? m['photo_key']),
      earnings: _double(m['earnings']),
      assignedAt: _str(m['assignedAt'] ?? m['assigned_at']),
      acceptedAt: _str(m['acceptedAt'] ?? m['accepted_at']),
      pickedUpAt: _str(m['pickedUpAt'] ?? m['picked_up_at']),
      outForDeliveryAt: _str(m['outForDeliveryAt'] ?? m['out_for_delivery_at']),
      reachedAt: _str(m['reachedAt'] ?? m['reached_at']),
      deliveredAt: _str(m['deliveredAt'] ?? m['delivered_at']),
    );
  }

  @override
  List<Object?> get props => [
        id,
        orderCode,
        status,
        attemptNo,
        customerName,
        customerPhone,
        address,
        destLat,
        destLng,
        distanceKm,
        amount,
        paymentMethod,
        paymentStatus,
        itemCount,
        otpVerified,
        manualVerificationRequired,
        failureReason,
        photoKey,
        earnings,
        assignedAt,
        acceptedAt,
        pickedUpAt,
        outForDeliveryAt,
        reachedAt,
        deliveredAt,
      ];
}

/// A parsed actionable-envelope error from a non-2xx delivery response.
///
/// The backend returns
/// `{success:false, code, title, message, action, retryable, severity,
///   nextStep, error:{code,message}}` on failure. This surfaces the bits the
/// UI shows and the `code` callers branch on (e.g.
/// `DELIVERY_LOCATION_MISMATCH`, `INVALID_DELIVERY_OTP`,
/// `MANUAL_VERIFICATION_REQUIRED`).
/// Delivery-specific [ApiException] so `catch`/`is DeliveryApiException` checks
/// keep working; parsing + [display] are inherited from the shared base.
class DeliveryApiException extends ApiException {
  DeliveryApiException({
    required super.code,
    required super.title,
    required super.message,
    super.nextStep,
    super.statusCode,
  });

  factory DeliveryApiException.fromResponse(Response<dynamic>? res) {
    final f = ApiException.parse(res);
    return DeliveryApiException(
      code: f.code, title: f.title, message: f.message,
      nextStep: f.nextStep, statusCode: f.statusCode,
    );
  }
}

/// The result of uploading a proof-of-delivery photo to POST /uploads.
class UploadResult {
  const UploadResult({required this.key, required this.url});
  final String key;
  final String url;
}

/// Thin repository over [Api] for the production agent delivery endpoints.
///
/// All paths are relative to /api/v1. Each mutating call returns the refreshed
/// [AgentDelivery] parsed from the success envelope's `data`, or throws a
/// [DeliveryApiException] carrying the backend envelope on any non-2xx.
class DeliveriesRepo {
  DeliveriesRepo(this._api);
  final Api _api;

  /// Throw a [DeliveryApiException] if [res] is a non-2xx (Dio's validateStatus
  /// lets 4xx through as data), otherwise return it.
  Response<dynamic> _ensureOk(Response<dynamic> res) {
    final code = res.statusCode ?? 0;
    if (code >= 400) {
      throw DeliveryApiException.fromResponse(res);
    }
    return res;
  }

  AgentDelivery _parse(Response<dynamic> res) =>
      AgentDelivery.fromMap(_api.obj(res.data));

  /// GET /deliveries/assigned → active tasks assigned to the signed-in agent.
  Future<List<AgentDelivery>> assigned() async {
    final res = _ensureOk(await _api.get('/deliveries/assigned'));
    return _api.list(res.data).map(AgentDelivery.fromMap).toList();
  }

  /// GET /deliveries/{id} → full task detail.
  Future<AgentDelivery> detail(String id) async {
    final res = _ensureOk(await _api.get('/deliveries/$id'));
    return _parse(res);
  }

  /// POST /deliveries/{id}/accept
  Future<AgentDelivery> accept(String id) async =>
      _parse(_ensureOk(await _api.post('/deliveries/$id/accept')));

  /// POST /deliveries/{id}/reject {reason}
  Future<AgentDelivery> reject(String id, String reason) async => _parse(
      _ensureOk(await _api.post('/deliveries/$id/reject',
          data: {'reason': reason})));

  /// POST /deliveries/{id}/pickup
  Future<AgentDelivery> pickup(String id) async =>
      _parse(_ensureOk(await _api.post('/deliveries/$id/pickup')));

  /// POST /deliveries/{id}/out-for-delivery — also sends the OTP to the
  /// customer.
  Future<AgentDelivery> outForDelivery(String id) async => _parse(
      _ensureOk(await _api.post('/deliveries/$id/out-for-delivery')));

  /// POST /deliveries/{id}/arrive {latitude, longitude}
  /// → 409 DELIVERY_LOCATION_MISMATCH when more than 50m from the destination.
  Future<AgentDelivery> arrive(
    String id, {
    required double latitude,
    required double longitude,
  }) async =>
      _parse(_ensureOk(await _api.post('/deliveries/$id/arrive',
          data: {'latitude': latitude, 'longitude': longitude})));

  /// POST /deliveries/{id}/otp {otp}
  /// → 400 INVALID_DELIVERY_OTP (message states attempts left) /
  ///   423 MANUAL_VERIFICATION_REQUIRED after 3 wrong attempts.
  Future<AgentDelivery> verifyOtp(String id, String otp) async => _parse(
      _ensureOk(await _api.post('/deliveries/$id/otp', data: {'otp': otp})));

  /// POST /deliveries/{id}/photo {photo_key, latitude, longitude}
  /// — mandatory proof-of-delivery before /complete.
  Future<AgentDelivery> attachPhoto(
    String id, {
    required String photoKey,
    required double latitude,
    required double longitude,
  }) async =>
      _parse(_ensureOk(await _api.post('/deliveries/$id/photo', data: {
        'photo_key': photoKey,
        'latitude': latitude,
        'longitude': longitude,
      })));

  /// POST /deliveries/{id}/return — the agent starts bringing failed goods
  /// back; the STORE confirms physical receipt from its panel (that's when
  /// stock restores and the order closes).
  Future<AgentDelivery> initiateReturn(String id) async =>
      _parse(_ensureOk(await _api.post('/deliveries/$id/return')));

  /// POST /deliveries/{id}/collect-cash — confirm the customer's COD cash:
  /// order → PAID and the notes enter the cash book (in-hand + deposits).
  /// Returns the updated task; the response also carries `cashInHand`.
  Future<({AgentDelivery delivery, double cashInHand})> collectCash(
      String id) async {
    final res =
        _ensureOk(await _api.post('/deliveries/$id/collect-cash'));
    final d = _api.obj(res.data);
    return (
      delivery: AgentDelivery.fromMap(d),
      cashInHand: _double(d['cashInHand']),
    );
  }

  /// GET /deliveries/cash-in-hand → what this agent is carrying.
  Future<({double inHand, int collections})> cashInHand() async {
    final res = _ensureOk(await _api.get('/deliveries/cash-in-hand'));
    final d = _api.obj(res.data);
    return (
      inHand: _double(d['inHand'] ?? d['in_hand']),
      collections: _int(d['collections']),
    );
  }

  /// POST /deliveries/{id}/complete → success code DELIVERY_COMPLETED.
  /// 409 if not (reached + otp verified + photo).
  Future<AgentDelivery> complete(String id) async =>
      _parse(_ensureOk(await _api.post('/deliveries/$id/complete')));

  /// POST /deliveries/{id}/fail {reason_code, note, photo_key?}
  Future<AgentDelivery> fail(
    String id, {
    required DeliveryFailReason reason,
    String note = '',
    String? photoKey,
  }) async {
    final body = <String, dynamic>{
      'reason_code': reason.code,
      'note': note,
    };
    if (photoKey != null && photoKey.isNotEmpty) {
      body['photo_key'] = photoKey;
    }
    return _parse(_ensureOk(await _api.post('/deliveries/$id/fail', data: body)));
  }

  /// POST /deliveries/location {latitude, longitude, task_id?, accuracy_m}
  /// — fire-and-forget GPS ping. Either while out for delivery (~every 15s,
  /// with [taskId]) or, with [taskId] omitted, a general "I'm on duty and
  /// here" presence ping (see PresenceController) that keeps dispatch's
  /// distance scoring current for an available agent between tasks. Errors
  /// are swallowed so a transient failure never disrupts the flow.
  Future<void> postLocation({
    String? taskId,
    required double latitude,
    required double longitude,
    double accuracyM = 0,
  }) async {
    try {
      await _api.post('/deliveries/location', data: {
        'latitude': latitude,
        'longitude': longitude,
        if (taskId != null && taskId.isNotEmpty) 'task_id': taskId,
        'accuracy_m': accuracyM,
      });
    } catch (_) {
      // Best-effort breadcrumb — never surface to the agent.
    }
  }

  /// Attach the proof-of-delivery photo in ONE multipart call to
  /// `POST /deliveries/{id}/photo` — the backend ingests it through the media
  /// engine (validated, EXIF-stripped, WebP variants) and stores the asset id.
  ///
  /// This replaces a two-step dance through the legacy `/uploads` stub, which
  /// DISCARDED the bytes and minted a key nobody could ever view: the agent was
  /// told "photo attached" while the store/customer saw a broken image.
  Future<AgentDelivery> attachPhotoFile(
    String id, {
    required List<int> bytes,
    required String filename,
    required double latitude,
    required double longitude,
  }) async {
    final form = FormData.fromMap({
      'photo': MultipartFile.fromBytes(bytes, filename: filename),
      'latitude': latitude,
      'longitude': longitude,
    });
    return _parse(
        _ensureOk(await _api.postMultipart('/deliveries/$id/photo', form)));
  }
}
