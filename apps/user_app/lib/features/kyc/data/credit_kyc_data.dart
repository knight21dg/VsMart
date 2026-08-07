import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/constants/api_constants.dart';
import '../../../core/errors/exceptions.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/providers/core_providers.dart';

/// Result of a PASSED CIBIL check — the customer's verified score.
class CreditCheckResult {
  const CreditCheckResult({
    required this.score,
    required this.band,
    required this.bureauName,
  });

  final int score;
  final String band;
  final String bureauName;
}

/// Data source for the two-phase credit apply flow:
///   1. [checkCibil]  → POST /kyc/credit/check   (name/DOB/PAN → gated CIBIL pull)
///   2. [submitDocuments] → POST /kyc/credit/submit (4 scans → agent verification)
/// The CIBIL score is pulled for the user's own registered number server-side.
class CreditKycDataSource {
  CreditKycDataSource(this._client);

  final ApiClient _client;

  Map<String, dynamic> _obj(dynamic raw) {
    final data = raw is Map && raw['data'] is Map ? raw['data'] : raw;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// Phase 1: verify identity + CIBIL. On a pass, returns the score. On a gated
  /// failure the backend blocks with a coded reason — 4xx failures (name/PAN
  /// mismatch) throw via the client; a 200 "soft" failure (low score / no record)
  /// is turned into a [ServerException] carrying the reason so the UI shows it.
  Future<CreditCheckResult> checkCibil({
    required String fullName,
    required String dob,
    required String pan,
    required bool consent,
  }) async {
    final res = await _client.post<dynamic>(
      ApiConstants.kycCreditCheck,
      data: {'fullName': fullName, 'dob': dob, 'pan': pan, 'consent': consent},
    );
    final raw = res.data;
    final ok = raw is Map && raw['success'] == true;
    if (!ok) {
      final msg = (raw is Map ? raw['message'] : null)?.toString();
      throw ServerException(
        (msg != null && msg.isNotEmpty)
            ? msg
            : 'Could not verify your credit details.',
        statusCode: res.statusCode ?? 200,
        data: raw,
      );
    }
    final j = _obj(raw);
    return CreditCheckResult(
      score: (j['score'] as num?)?.toInt() ?? 0,
      band: (j['band'] ?? '').toString(),
      bureauName: (j['bureauName'] ?? '').toString(),
    );
  }

  /// Phase 2: upload the Aadhaar + PAN scans (both sides). Requires a passed
  /// check first (the backend enforces this). Field names are camelCase; the
  /// four scan fields are multipart files.
  Future<void> submitDocuments({
    required bool consent,
    required String aadhaarFrontPath,
    required String aadhaarBackPath,
    required String panFrontPath,
    required String panBackPath,
  }) async {
    final form = FormData.fromMap({
      'consent': consent.toString(),
      'aadhaarFront': await MultipartFile.fromFile(aadhaarFrontPath,
          filename: 'aadhaar_front.jpg'),
      'aadhaarBack': await MultipartFile.fromFile(aadhaarBackPath,
          filename: 'aadhaar_back.jpg'),
      'panFront':
          await MultipartFile.fromFile(panFrontPath, filename: 'pan_front.jpg'),
      'panBack':
          await MultipartFile.fromFile(panBackPath, filename: 'pan_back.jpg'),
    });
    await _client.post<dynamic>(ApiConstants.kycCreditSubmit, data: form);
  }
}

final creditKycDataSourceProvider = Provider<CreditKycDataSource>(
  (ref) => CreditKycDataSource(ref.watch(apiClientProvider)),
);
