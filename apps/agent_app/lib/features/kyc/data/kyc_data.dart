import 'package:equatable/equatable.dart';

import '../../../core/api.dart';

// ── parse helpers (null-safe across String / null) ──
String _str(dynamic v) => v == null ? '' : v.toString();

/// One verification step on a KYC application.
/// Backed by VerificationStep: step ∈ {aadhaar,pan,selfie,residence,credit},
/// status ∈ {pending,in_review,approved,rejected}.
class KycStep extends Equatable {
  const KycStep({required this.step, required this.status, required this.note});

  final String step;
  final String status;
  final String note;

  factory KycStep.fromMap(Map<String, dynamic> m) => KycStep(
        step: _str(m['step']),
        status: _str(m['status']),
        note: _str(m['note']),
      );

  @override
  List<Object?> get props => [step, status, note];
}

/// One uploaded document on a KYC application.
/// Backed by KycDocument: type, number_masked, status.
class KycDoc extends Equatable {
  const KycDoc({
    required this.id,
    required this.type,
    required this.numberMasked,
    required this.status,
    required this.hasFile,
  });

  final String id;
  final String type;
  final String numberMasked;
  final String status;
  final bool hasFile;

  /// Auth-gated bytes endpoint for this document's image (served to reviewers by
  /// the backend `DocumentFileView`; never a raw MEDIA url).
  String get filePath => '/kyc/documents/$id/file';

  factory KycDoc.fromMap(Map<String, dynamic> m) => KycDoc(
        id: _str(m['id']),
        type: _str(m['type']),
        // accept both camelCase and the backend's snake_case.
        numberMasked: _str(m['numberMasked'] ?? m['number_masked']),
        status: _str(m['status']),
        // serializer sends a non-null `url` only when a file is stored.
        hasFile: _str(m['url'] ?? m['fileUrl']).isNotEmpty,
      );

  @override
  List<Object?> get props => [id, type, numberMasked, status, hasFile];
}

/// A KYC application in the agent review queue (GET /agent/kyc/queue).
class KycApplicationModel extends Equatable {
  const KycApplicationModel({
    this.id,
    required this.status,
    required this.submittedAt,
    required this.steps,
    required this.documents,
  });

  final String? id;
  final String status;
  final String submittedAt;
  final List<KycStep> steps;
  final List<KycDoc> documents;

  bool get hasId => id != null && id!.isNotEmpty;

  factory KycApplicationModel.fromMap(Map<String, dynamic> m) {
    final rawSteps = m['steps'];
    final steps = rawSteps is List
        ? rawSteps
            .whereType<Map>()
            .map((e) => KycStep.fromMap(Map<String, dynamic>.from(e)))
            .toList()
        : <KycStep>[];
    final rawDocs = m['documents'];
    final docs = rawDocs is List
        ? rawDocs
            .whereType<Map>()
            .map((e) => KycDoc.fromMap(Map<String, dynamic>.from(e)))
            .toList()
        : <KycDoc>[];
    final rawId = m['id'] ?? m['pk'];
    return KycApplicationModel(
      id: rawId?.toString(),
      status: _str(m['status']),
      // accept both camelCase and the backend's snake_case.
      submittedAt: _str(m['submittedAt'] ?? m['submitted_at']),
      steps: steps,
      documents: docs,
    );
  }

  @override
  List<Object?> get props => [id, status, submittedAt, steps, documents];
}

/// Thin repository over [Api] for the agent KYC review endpoints.
class KycRepo {
  KycRepo(this._api);
  final Api _api;

  /// GET /agent/kyc/queue → list of pending applications.
  Future<List<KycApplicationModel>> queue() async {
    final res = _api.ensureOk(await _api.get('/agent/kyc/queue'));
    return _api
        .list(res.data)
        .map(KycApplicationModel.fromMap)
        .toList();
  }

  /// `POST /agent/kyc/<id>/review` with body {step, decision, note}.
  /// [decision] is 'approve' or 'reject'. Returns the FULL updated
  /// application (the backend already sends it back — AgentReviewView
  /// returns `KycApplicationSerializer(app).data`) so the caller can refresh
  /// its view of this application without a separate detail fetch (there
  /// isn't one — only GET /agent/kyc/queue and this review endpoint exist).
  Future<KycApplicationModel> review({
    required String id,
    required String step,
    required String decision,
    String? note,
  }) async {
    final res = _api.ensureOk(await _api.post('/agent/kyc/$id/review', data: {
      'step': step,
      'decision': decision,
      if (note != null && note.isNotEmpty) 'note': note,
    }));
    return KycApplicationModel.fromMap(_api.obj(res.data));
  }
}
