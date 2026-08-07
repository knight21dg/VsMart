import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../../app/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/verification_application.dart';
import '../../domain/entities/verification_draft.dart';
import '../../domain/entities/verification_enums.dart';
import '../../domain/entities/verification_result.dart';
import 'verification_data_source.dart';

/// [VerificationDataSource] backed by the backend KYC API: `POST /kyc/submit`,
/// `GET /kyc/status`.
class VerificationBackendDataSource implements VerificationDataSource {
  VerificationBackendDataSource(this._client);

  final ApiClient _client;

  Map<String, dynamic> _obj(dynamic raw) {
    final data = raw is Map && raw['data'] is Map ? raw['data'] : raw;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  @override
  Future<VerificationApplication> submit(VerificationDraft draft) async {
    // Send the collected identity documents (masked numbers) AND the actual
    // captured image bytes as multipart, so the backend persists real KYC files.
    final documents = <Map<String, dynamic>>[
      if (draft.aadhaarNumber.isNotEmpty)
        {'type': 'aadhaar', 'number_masked': _mask(draft.aadhaarNumber)},
      if (draft.panNumber.isNotEmpty)
        {'type': 'pan', 'number_masked': _mask(draft.panNumber)},
      if (draft.selfiePath != null) {'type': 'selfie'},
    ];

    final fields = <String, dynamic>{'documents': jsonEncode(documents)};
    // The backend reads file fields named aadhaar / pan / selfie / residence.
    final aadhaar = draft.aadhaarFrontPath;
    if (aadhaar != null) {
      fields['aadhaar'] =
          await MultipartFile.fromFile(aadhaar, filename: 'aadhaar.jpg');
    }
    final pan = draft.panPath;
    if (pan != null) {
      fields['pan'] = await MultipartFile.fromFile(pan, filename: 'pan.jpg');
    }
    final selfie = draft.selfiePath;
    if (selfie != null) {
      fields['selfie'] =
          await MultipartFile.fromFile(selfie, filename: 'selfie.jpg');
    }

    final res = await _client.post<dynamic>(
      ApiConstants.kycSubmit,
      data: FormData.fromMap(fields),
    );
    return _toApp(_obj(res.data));
  }

  @override
  Future<VerificationApplication> submitResidence({
    required String photoPath,
    required double latitude,
    required double longitude,
  }) async {
    // The backend persists latitude/longitude from each document's metadata
    // onto the matching `residence` KycDocument (see kyc.services.submit), and
    // reads the photo bytes from the multipart file keyed by the document type.
    final documents = <Map<String, dynamic>>[
      {'type': 'residence', 'latitude': latitude, 'longitude': longitude},
    ];
    final fields = <String, dynamic>{
      'documents': jsonEncode(documents),
      'residence':
          await MultipartFile.fromFile(photoPath, filename: 'residence.jpg'),
    };

    final res = await _client.post<dynamic>(
      ApiConstants.kycSubmit,
      data: FormData.fromMap(fields),
    );
    return _toApp(_obj(res.data));
  }

  /// Mask all but the last 4 chars (e.g. Aadhaar/PAN) for safe storage/display.
  String _mask(String value) {
    final v = value.replaceAll(RegExp(r'\s+'), '');
    if (v.length <= 4) return v;
    return '${'X' * (v.length - 4)}${v.substring(v.length - 4)}';
  }

  @override
  Future<VerificationApplication> getApplication() async {
    final res = await _client.get<dynamic>(ApiConstants.kycStatus);
    return _toApp(_obj(res.data));
  }

  @override
  Future<VerificationApplication> retry() async {
    final res = await _client.post<dynamic>(ApiConstants.kycRetry);
    return _toApp(_obj(res.data));
  }

  @override
  Future<VerificationResult> verifyPan({
    required String pan,
    required String name,
    required bool consent,
  }) async {
    final res = await _client.post<dynamic>(
      ApiConstants.kycPanVerify,
      data: {'pan': pan, 'name': name, 'consent': consent},
    );
    return VerificationResult.fromJson(_obj(res.data));
  }

  @override
  Future<VerificationResult> sendAadhaarOtp({required String aadhaar}) async {
    final res = await _client.post<dynamic>(
      ApiConstants.kycAadhaarSendOtp,
      data: {'aadhaar': aadhaar},
    );
    // send-otp returns {reference_id}; model it as a PENDING aadhaar result.
    final data = _obj(res.data);
    return VerificationResult(
      kind: 'aadhaar',
      status: 'pending',
      referenceId: data['referenceId']?.toString() ?? '',
    );
  }

  @override
  Future<VerificationResult> verifyAadhaarOtp({
    required String referenceId,
    required String otp,
    required String aadhaar,
  }) async {
    final res = await _client.post<dynamic>(
      ApiConstants.kycAadhaarVerifyOtp,
      data: {'reference_id': referenceId, 'otp': otp, 'aadhaar': aadhaar},
    );
    return VerificationResult.fromJson(_obj(res.data));
  }

  VerificationApplication _toApp(Map<String, dynamic> j) => VerificationApplication(
        applicationId: 'VSKYC',
        status: _status(j['status']?.toString()),
        submittedAt:
            DateTime.tryParse(j['submittedAt']?.toString() ?? '')?.toLocal() ??
                DateTime.now(),
        rejectionReason: j['rejectionReason'] as String?,
      );

  // Backend KYC statuses: not_started / pending / verified / rejected.
  VerificationStatus _status(String? s) => switch (s) {
        'pending' => VerificationStatus.pending,
        'approved' || 'verified' => VerificationStatus.approved,
        'rejected' => VerificationStatus.rejected,
        _ => VerificationStatus.notStarted,
      };
}
