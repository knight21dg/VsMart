import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/providers.dart';

String _str(dynamic v) => v == null ? '' : v.toString();

/// The document types the backend accepts as file uploads on `/kyc/submit`
/// (`kyc.views.FILE_DOC_TYPES`). Kept in the same order the agent is asked for
/// them so the form reads like a checklist.
const kycDocTypes = <String, String>{
  'aadhaar': 'Aadhaar card',
  'pan': 'PAN card',
  'selfie': 'Selfie',
  'residence': 'Address proof',
};

/// One uploaded document on the agent's own KYC application.
class MyKycDocument extends Equatable {
  const MyKycDocument({required this.id, required this.type, required this.status});

  final String id;
  final String type;
  final String status;

  String get label => kycDocTypes[type] ?? type;

  factory MyKycDocument.fromMap(Map<String, dynamic> m) => MyKycDocument(
        id: _str(m['id']),
        type: _str(m['type']),
        status: _str(m['status']),
      );

  @override
  List<Object?> get props => [id, type, status];
}

/// The agent's OWN KYC application — not the customer queue they review.
///
/// The agent app only ever had the reviewer side (`/agent/kyc/queue`), so an
/// agent whose own KYC was pending or rejected saw a read-only status word on
/// their profile and had no way to do anything about it. The backend's
/// `/kyc/status` and `/kyc/submit` are role-agnostic (they key on
/// `request.user`), so this is the same machinery the customer app uses.
class MyKyc extends Equatable {
  const MyKyc({
    required this.status,
    required this.rejectionReason,
    required this.submittedAt,
    required this.documents,
  });

  final String status;
  final String rejectionReason;
  final String submittedAt;
  final List<MyKycDocument> documents;

  bool get isVerified => status == 'verified';
  bool get isPending => status == 'pending' || status == 'in_review';
  bool get isRejected => status == 'rejected';

  /// Whether the agent may submit (or re-submit) documents right now. A pending
  /// application is with a reviewer — letting them re-upload would reset the
  /// queue position and confuse the reviewer mid-decision.
  bool get canSubmit => !isVerified && !isPending;

  Set<String> get uploadedTypes => documents.map((d) => d.type).toSet();

  factory MyKyc.fromMap(Map<String, dynamic> m) => MyKyc(
        status: _str(m['status']).isEmpty ? 'not_started' : _str(m['status']),
        rejectionReason: _str(m['rejectionReason'] ?? m['rejection_reason']),
        submittedAt: _str(m['submittedAt'] ?? m['submitted_at']),
        documents: (m['documents'] is List ? m['documents'] as List : const [])
            .whereType<Map>()
            .map((d) => MyKycDocument.fromMap(Map<String, dynamic>.from(d)))
            .toList(),
      );

  @override
  List<Object?> get props => [status, rejectionReason, submittedAt, documents];
}

class MyKycRepo {
  MyKycRepo(this._api);
  final Api _api;

  Future<MyKyc> status() async {
    final res = _api.ensureOk(await _api.get('/kyc/status'));
    return MyKyc.fromMap(_api.obj(res.data));
  }

  /// Upload the captured documents in ONE multipart submit.
  ///
  /// One request, not one per document: `/kyc/submit` transitions the whole
  /// application to `pending`, so submitting per-file would move it to review
  /// after the first document and leave the rest orphaned on a locked
  /// application.
  Future<MyKyc> submit(Map<String, ({List<int> bytes, String filename})> files) async {
    final form = FormData.fromMap({
      for (final entry in files.entries)
        entry.key: MultipartFile.fromBytes(
          entry.value.bytes,
          filename: entry.value.filename,
        ),
    });
    final res = _api.ensureOk(await _api.postMultipart('/kyc/submit', form));
    return MyKyc.fromMap(_api.obj(res.data));
  }
}

final myKycRepoProvider =
    Provider<MyKycRepo>((ref) => MyKycRepo(ref.watch(apiProvider)));

final myKycProvider = FutureProvider<MyKyc>(
  (ref) => ref.watch(myKycRepoProvider).status(),
);
