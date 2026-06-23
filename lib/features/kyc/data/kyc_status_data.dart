import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/providers/core_providers.dart';

/// A single KYC document as the backend records it (`GET /kyc/status`).
class KycDocumentInfo {
  const KycDocumentInfo({
    required this.type,
    required this.numberMasked,
    required this.status,
    this.url,
  });

  /// aadhaar / pan / selfie / residence.
  final String type;
  final String numberMasked;

  /// pending / verified / rejected.
  final String status;
  final String? url;

  String get label => switch (type) {
        'aadhaar' => 'Aadhaar Card',
        'pan' => 'PAN Card',
        'selfie' => 'Selfie / Video KYC',
        'residence' => 'Address Proof',
        _ => type,
      };
}

/// The customer's KYC standing, straight from the backend.
class KycStatusInfo {
  const KycStatusInfo({
    required this.status,
    required this.documents,
    this.submittedAt,
    this.rejectionReason,
  });

  /// not_started / pending / verified / rejected.
  final String status;
  final List<KycDocumentInfo> documents;
  final DateTime? submittedAt;
  final String? rejectionReason;

  bool get isVerified => status == 'verified' || status == 'approved';
  bool get isPending => status == 'pending';
  bool get isRejected => status == 'rejected';
  bool get isNotStarted =>
      status.isEmpty || status == 'not_started' || status == 'notStarted';

  /// Completion fraction for the status banner.
  double get progress => isVerified
      ? 1
      : isPending
          ? 0.66
          : isRejected
              ? 0.33
              : 0;
}

class KycStatusDataSource {
  KycStatusDataSource(this._client);

  final ApiClient _client;

  Map<String, dynamic> _obj(dynamic raw) {
    final data = raw is Map && raw['data'] is Map ? raw['data'] : raw;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<KycStatusInfo> fetch() async {
    final res = await _client.get<dynamic>(ApiConstants.kycStatus);
    final j = _obj(res.data);
    final docs = ((j['documents'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) {
          final d = Map<String, dynamic>.from(e);
          return KycDocumentInfo(
            type: (d['type'] ?? '').toString(),
            numberMasked: (d['numberMasked'] ?? '').toString(),
            status: (d['status'] ?? 'pending').toString(),
            url: d['url'] as String?,
          );
        })
        .toList();
    return KycStatusInfo(
      status: (j['status'] ?? '').toString(),
      documents: docs,
      submittedAt:
          DateTime.tryParse(j['submittedAt']?.toString() ?? '')?.toLocal(),
      rejectionReason: j['rejectionReason'] as String?,
    );
  }
}

final kycStatusDataSourceProvider = Provider<KycStatusDataSource>(
  (ref) => KycStatusDataSource(ref.watch(apiClientProvider)),
);

final kycStatusProvider = FutureProvider<KycStatusInfo>(
  (ref) => ref.watch(kycStatusDataSourceProvider).fetch(),
);
