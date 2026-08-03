import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';

import '../../../core/api.dart';
import '../../../core/api_exception.dart';

// ── parse helpers (null-safe across num / String / null) ──
double? _doubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

String _str(dynamic v) => v == null ? '' : v.toString();

/// One captured piece of field evidence on a verification task.
/// kind ∈ {photo, gps, document}.
class VerificationEvidence extends Equatable {
  const VerificationEvidence({
    required this.id,
    required this.taskId,
    required this.kind,
    required this.photoKey,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
  });

  final String id;
  final String taskId;
  final String kind;
  final String photoKey;
  final double? latitude;
  final double? longitude;
  final String createdAt;

  bool get isGps => kind == 'gps';
  bool get isPhoto => kind == 'photo';
  bool get hasCoords => latitude != null && longitude != null;

  factory VerificationEvidence.fromMap(Map<String, dynamic> m) {
    return VerificationEvidence(
      id: _str(m['id']),
      taskId: _str(m['taskId'] ?? m['task_id']),
      kind: _str(m['kind']),
      photoKey: _str(m['photoKey'] ?? m['photo_key']),
      latitude: _doubleOrNull(m['latitude']),
      longitude: _doubleOrNull(m['longitude']),
      createdAt: _str(m['createdAt'] ?? m['created_at']),
    );
  }

  @override
  List<Object?> get props =>
      [id, taskId, kind, photoKey, latitude, longitude, createdAt];
}

/// A field-verification task assigned to the agent.
///
/// type ∈ {kyc, residence, credit};
/// status ∈ {pending, assigned, in_progress, submitted, approved, rejected}.
class VerificationTask extends Equatable {
  const VerificationTask({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.agentId,
    required this.type,
    required this.status,
    required this.note,
    required this.submittedAt,
    required this.createdAt,
    required this.evidence,
  });

  final String id;
  final String customerId;
  final String customerName;
  final String agentId;
  final String type;
  final String status;
  final String note;
  final String submittedAt;
  final String createdAt;
  final List<VerificationEvidence> evidence;

  bool get isClaimable => status == 'pending' || status == 'assigned';
  bool get isInProgress => status == 'in_progress';
  bool get isTerminal =>
      status == 'submitted' || status == 'approved' || status == 'rejected';

  factory VerificationTask.fromMap(Map<String, dynamic> m) {
    final rawEvidence = m['evidence'];
    final evidence = rawEvidence is List
        ? rawEvidence
            .whereType<Map>()
            .map((e) =>
                VerificationEvidence.fromMap(Map<String, dynamic>.from(e)))
            .toList()
        : <VerificationEvidence>[];
    return VerificationTask(
      id: _str(m['id']),
      customerId: _str(m['customerId'] ?? m['customer_id']),
      customerName: _str(m['customerName'] ?? m['customer_name']),
      agentId: _str(m['agentId'] ?? m['agent_id']),
      type: _str(m['type']),
      status: _str(m['status']),
      note: _str(m['note']),
      submittedAt: _str(m['submittedAt'] ?? m['submitted_at']),
      createdAt: _str(m['createdAt'] ?? m['created_at']),
      evidence: evidence,
    );
  }

  @override
  List<Object?> get props => [
        id,
        customerId,
        customerName,
        agentId,
        type,
        status,
        note,
        submittedAt,
        createdAt,
        evidence,
      ];
}

/// A parsed actionable-envelope error from a non-2xx verification response.
///
/// The backend returns
/// `{success:false, code, title, message, action, retryable, severity,
///   nextStep, error:{code,message}}` on failure. Mirrors the delivery /
/// collection exception parsers.
/// Verification-specific [ApiException]; parsing + [display] inherited from base.
class VerificationApiException extends ApiException {
  VerificationApiException({
    required super.code,
    required super.title,
    required super.message,
    super.nextStep,
    super.statusCode,
  });

  factory VerificationApiException.fromResponse(Response<dynamic>? res) {
    final f = ApiException.parse(res);
    return VerificationApiException(
      code: f.code, title: f.title, message: f.message,
      nextStep: f.nextStep, statusCode: f.statusCode,
    );
  }
}

/// The result of uploading a photo to POST /uploads.
class UploadResult {
  const UploadResult({required this.key, required this.url});
  final String key;
  final String url;
}

/// Thin repository over [Api] for the field-verification endpoints.
///
/// All paths are relative to /api/v1. Each call throws a
/// [VerificationApiException] carrying the backend envelope on any non-2xx.
class VerificationRepo {
  VerificationRepo(this._api);
  final Api _api;

  Response<dynamic> _ensureOk(Response<dynamic> res) {
    if ((res.statusCode ?? 0) >= 400) {
      throw VerificationApiException.fromResponse(res);
    }
    return res;
  }

  VerificationTask _parse(Response<dynamic> res) =>
      VerificationTask.fromMap(_api.obj(res.data));

  /// GET /verification/tasks → tasks assigned to / available for the agent.
  Future<List<VerificationTask>> tasks() async {
    final res = _ensureOk(await _api.get('/verification/tasks'));
    return _api.list(res.data).map(VerificationTask.fromMap).toList();
  }

  /// GET /verification/tasks/{id} → full task detail incl. evidence.
  Future<VerificationTask> detail(String id) async {
    final res = _ensureOk(await _api.get('/verification/tasks/$id'));
    return _parse(res);
  }

  /// POST /verification/tasks/{id}/start → claim the task (→ in_progress).
  Future<VerificationTask> start(String id) async =>
      _parse(_ensureOk(await _api.post('/verification/tasks/$id/start')));

  /// POST /verification/gps {task_id, latitude, longitude} → 201 evidence.
  Future<VerificationEvidence> captureGps(
    String taskId, {
    required double latitude,
    required double longitude,
  }) async {
    final res = _ensureOk(await _api.post('/verification/gps', data: {
      'task_id': taskId,
      'latitude': latitude,
      'longitude': longitude,
    }));
    return VerificationEvidence.fromMap(_api.obj(res.data));
  }

  /// POST /verification/photo {task_id, photo_key} → 201 evidence.
  Future<VerificationEvidence> capturePhoto(
    String taskId, {
    required String photoKey,
  }) async {
    final res = _ensureOk(await _api.post('/verification/photo', data: {
      'task_id': taskId,
      'photo_key': photoKey,
    }));
    return VerificationEvidence.fromMap(_api.obj(res.data));
  }

  /// One multipart call: the photo file goes straight to `/verification/photo`
  /// and the backend's media engine stores it as a viewable private asset.
  /// (The old two-step via the legacy `/uploads` stub discarded the bytes.)
  Future<VerificationEvidence> capturePhotoFile(
    String taskId, {
    required List<int> bytes,
    required String filename,
  }) async {
    final form = FormData.fromMap({
      'task_id': taskId,
      'photo': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final res =
        _ensureOk(await _api.postMultipart('/verification/photo', form));
    return VerificationEvidence.fromMap(_api.obj(res.data));
  }

  /// POST /verification/tasks/{id}/submit {decision?, note?}
  /// → submitted / approved / rejected.
  Future<VerificationTask> submit(
    String id, {
    String? decision,
    String? note,
  }) async {
    final body = <String, dynamic>{};
    if (decision != null && decision.isNotEmpty) body['decision'] = decision;
    if (note != null && note.isNotEmpty) body['note'] = note;
    return _parse(_ensureOk(await _api.post('/verification/tasks/$id/submit',
        data: body.isEmpty ? null : body)));
  }

  /// POST /uploads (multipart field 'file') → {key, url}. Used to obtain the
  /// `photo_key` for the photo-evidence call.
  Future<UploadResult> uploadFile({
    required List<int> bytes,
    required String filename,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final res = _ensureOk(await _api.postMultipart('/uploads', form));
    final d = _api.obj(res.data);
    return UploadResult(key: _str(d['key']), url: _str(d['url']));
  }
}
