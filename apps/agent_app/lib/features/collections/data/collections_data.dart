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

bool _bool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }
  return false;
}

/// Failure reason codes accepted by POST /collections/{id}/fail.
enum CollectionFailReason {
  customerNotAvailable('CUSTOMER_NOT_AVAILABLE', 'Customer not available'),
  addressNotFound('FAILED_ADDRESS_NOT_FOUND', 'Address not found'),
  customerRejected('FAILED_CUSTOMER_REJECTED', 'Customer refused to pay'),
  securityConcern('FAILED_SECURITY_CONCERN', 'Security concern');

  const CollectionFailReason(this.code, this.label);
  final String code;
  final String label;
}

/// A cash-recovery task assigned to the agent — the production Collection state
/// machine record (GET /collections/assigned, GET /collections/{id}).
///
/// Statuses, in order:
///   requested/assigned → accepted → en_route → reached
///   → (otp verified) → (collect) → collected
/// plus the terminal `failed` / `rejected` / `cancelled` / `disputed`,
/// and `partially_collected` when an amount short of the full due is recovered.
class AgentCollection extends Equatable {
  const AgentCollection({
    required this.id,
    required this.status,
    required this.amount,
    required this.collectedAmount,
    required this.remaining,
    required this.isPriority,
    required this.escalated,
    required this.attemptNo,
    required this.otpVerified,
    required this.otpPending,
    required this.otpAmount,
    required this.manualVerificationRequired,
    required this.failureReason,
    required this.customerName,
    required this.customerPhone,
    this.customerLat,
    this.customerLng,
    this.address = '',
    required this.assignedAt,
    required this.acceptedAt,
    required this.enRouteAt,
    required this.reachedAt,
    required this.collectedAt,
    required this.createdAt,
  });

  /// Task id — the path segment for every state-machine call.
  final String id;
  final String status;

  /// Total amount to recover.
  final double amount;

  /// How much has been recovered so far.
  final double collectedAmount;

  /// Outstanding amount still due.
  final double remaining;
  final bool isPriority;
  final bool escalated;
  final int attemptNo;
  final bool otpVerified;

  /// An amount-bound OTP has been sent to the customer and is awaiting the code.
  final bool otpPending;

  /// The amount the pending / confirmed OTP authorises.
  final double otpAmount;
  final bool manualVerificationRequired;
  final String failureReason;
  final String customerName;
  final String customerPhone;

  /// Customer's location (their default address) — for the visit map. Null when
  /// the customer has no geocoded address on file.
  final double? customerLat;
  final double? customerLng;
  final String address;

  bool get hasLocation => customerLat != null && customerLng != null;

  final String assignedAt;
  final String acceptedAt;
  final String enRouteAt;
  final String reachedAt;
  final String collectedAt;
  final String createdAt;

  /// Best-effort outstanding figure: the backend `remaining`, falling back to
  /// (amount − collected) when the field is absent or zero.
  double get amountDue {
    if (remaining > 0) return remaining;
    final computed = amount - collectedAmount;
    return computed > 0 ? computed : 0;
  }

  factory AgentCollection.fromMap(Map<String, dynamic> m) {
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

    // `customer` may be a map ({name, phone}) or a plain name string.
    final customerName = custMap != null
        ? fromCustomer(['name'])
        : _str(m['customer'] ?? m['customerName'] ?? m['customer_name']);

    return AgentCollection(
      id: _str(m['id'] ?? m['taskId'] ?? m['task_id']),
      status: _str(m['status']),
      amount: _double(m['amount']),
      collectedAmount: _double(m['collectedAmount'] ?? m['collected_amount']),
      remaining: _double(m['remaining']),
      isPriority: _bool(m['isPriority'] ?? m['is_priority']),
      escalated: _bool(m['escalated']),
      attemptNo: _int(m['attemptNo'] ?? m['attempt_no']),
      otpVerified: _bool(m['otpVerified'] ?? m['otp_verified']),
      otpPending: _bool(m['otpPending'] ?? m['otp_pending']),
      otpAmount: _double(m['otpAmount'] ?? m['otp_amount']),
      manualVerificationRequired: _bool(
          m['manualVerificationRequired'] ?? m['manual_verification_required']),
      failureReason: _str(m['failureReason'] ?? m['failure_reason']),
      customerName: customerName,
      customerPhone: fromCustomer(['phone']).isNotEmpty
          ? fromCustomer(['phone'])
          : _str(m['customerPhone'] ?? m['customer_phone']),
      customerLat: _doubleOrNull(m['customerLat'] ?? m['customer_lat']),
      customerLng: _doubleOrNull(m['customerLng'] ?? m['customer_lng']),
      address: _str(m['address']),
      assignedAt: _str(m['assignedAt'] ?? m['assigned_at']),
      acceptedAt: _str(m['acceptedAt'] ?? m['accepted_at']),
      enRouteAt: _str(m['enRouteAt'] ?? m['en_route_at']),
      reachedAt: _str(m['reachedAt'] ?? m['reached_at']),
      collectedAt: _str(m['collectedAt'] ?? m['collected_at']),
      createdAt: _str(m['createdAt'] ?? m['created_at']),
    );
  }

  @override
  List<Object?> get props => [
        id,
        status,
        amount,
        collectedAmount,
        remaining,
        isPriority,
        escalated,
        attemptNo,
        otpVerified,
        manualVerificationRequired,
        failureReason,
        customerName,
        customerPhone,
        assignedAt,
        acceptedAt,
        enRouteAt,
        reachedAt,
        collectedAt,
        createdAt,
      ];
}

/// A parsed actionable-envelope error from a non-2xx collection response.
///
/// The backend returns
/// `{success:false, code, title, message, action, retryable, severity,
///   nextStep, error:{code,message}}` on failure. This surfaces the bits the
/// UI shows and the `code` callers branch on (e.g.
/// `INVALID_COLLECTION_OTP`, `COLLECTION_OTP_LOCKED`,
/// `COLLECTION_OTP_REQUIRED`, `COLLECTION_AMOUNT_INVALID`).
/// Collection-specific [ApiException]; parsing + [display] inherited from base.
class CollectionApiException extends ApiException {
  CollectionApiException({
    required super.code,
    required super.title,
    required super.message,
    super.nextStep,
    super.statusCode,
  });

  factory CollectionApiException.fromResponse(Response<dynamic>? res) {
    final f = ApiException.parse(res);
    return CollectionApiException(
      code: f.code, title: f.title, message: f.message,
      nextStep: f.nextStep, statusCode: f.statusCode,
    );
  }
}

/// The result of a successful POST /collections/{id}/collect.
///
/// Carries the refreshed task plus whether the backend reported a full
/// (`COLLECTION_COMPLETED`) or partial (`PARTIAL_PAYMENT`) recovery so the UI
/// can confirm the outcome and surface any remaining due.
class CollectResult {
  const CollectResult({required this.collection, required this.partial});
  final AgentCollection collection;
  final bool partial;
}

/// Thin repository over [Api] for the production agent collection endpoints.
///
/// All paths are relative to /api/v1. Each mutating call returns the refreshed
/// [AgentCollection] parsed from the success envelope's `data`, or throws a
/// [CollectionApiException] carrying the backend envelope on any non-2xx.
class CollectionsRepo {
  CollectionsRepo(this._api);
  final Api _api;

  /// Throw a [CollectionApiException] if [res] is a non-2xx (Dio's
  /// validateStatus lets 4xx through as data), otherwise return it.
  Response<dynamic> _ensureOk(Response<dynamic> res) {
    final code = res.statusCode ?? 0;
    if (code >= 400) {
      throw CollectionApiException.fromResponse(res);
    }
    return res;
  }

  AgentCollection _parse(Response<dynamic> res) =>
      AgentCollection.fromMap(_api.obj(res.data));

  /// GET /collections/assigned → active tasks assigned to the signed-in agent.
  Future<List<AgentCollection>> assigned() async {
    final res = _ensureOk(await _api.get('/collections/assigned'));
    return _api.list(res.data).map(AgentCollection.fromMap).toList();
  }

  /// GET /collections/{id} → full task detail.
  Future<AgentCollection> detail(String id) async {
    final res = _ensureOk(await _api.get('/collections/$id'));
    return _parse(res);
  }

  /// POST /collections/{id}/accept
  Future<AgentCollection> accept(String id) async =>
      _parse(_ensureOk(await _api.post('/collections/$id/accept')));

  /// POST /collections/{id}/reject {reason}
  Future<AgentCollection> reject(String id, String reason) async => _parse(
      _ensureOk(await _api.post('/collections/$id/reject',
          data: {'reason': reason})));

  /// POST /collections/{id}/en-route
  Future<AgentCollection> enRoute(String id) async =>
      _parse(_ensureOk(await _api.post('/collections/$id/en-route')));

  /// POST /collections/{id}/reach — mark arrival (no OTP yet).
  Future<AgentCollection> reach(String id) async =>
      _parse(_ensureOk(await _api.post('/collections/$id/reach')));

  /// POST /collections/{id}/request-otp {amount} — the agent enters the amount
  /// being collected; the customer gets an alert to confirm exactly that figure
  /// and shares the OTP.
  Future<AgentCollection> requestOtp(String id, double amount) async => _parse(
      _ensureOk(await _api
          .post('/collections/$id/request-otp', data: {'amount': amount})));

  /// POST /collections/{id}/otp {otp}
  /// → 400 INVALID_COLLECTION_OTP (message states attempts left) /
  ///   423 COLLECTION_OTP_LOCKED after 3 wrong attempts.
  Future<AgentCollection> verifyOtp(String id, String otp) async => _parse(
      _ensureOk(await _api.post('/collections/$id/otp', data: {'otp': otp})));

  /// POST /collections/{id}/collect {amount?}
  /// — omit [amount] to collect the full remaining due.
  /// → 409 COLLECTION_OTP_REQUIRED if not verified,
  ///   400 COLLECTION_AMOUNT_INVALID if amount > remaining;
  ///   success code COLLECTION_COMPLETED (full) or PARTIAL_PAYMENT (partial).
  Future<CollectResult> collect(String id, {double? amount}) async {
    final body = <String, dynamic>{};
    if (amount != null) body['amount'] = amount;
    final res = _ensureOk(await _api.post('/collections/$id/collect',
        data: body.isEmpty ? null : body));
    final raw = res.data;
    final code = (raw is Map ? _str(raw['code']) : '').toUpperCase();
    return CollectResult(collection: _parse(res), partial: code == 'PARTIAL_PAYMENT');
  }

  /// POST /collections/{id}/dispute {note}
  Future<AgentCollection> dispute(String id, String note) async => _parse(
      _ensureOk(await _api.post('/collections/$id/dispute',
          data: {'note': note})));

  /// POST /collections/{id}/fail {reason_code, note}
  Future<AgentCollection> fail(
    String id, {
    required CollectionFailReason reason,
    String note = '',
  }) async =>
      _parse(_ensureOk(await _api.post('/collections/$id/fail', data: {
        'reason_code': reason.code,
        'note': note,
      })));
}
