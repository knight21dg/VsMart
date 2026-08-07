import 'package:equatable/equatable.dart';

/// The outcome of one gov-source verification call (PAN / Aadhaar OTP / bank).
///
/// A *failure* (invalid PAN, wrong OTP, duplicate id) does not surface here — it
/// comes back as a coded [Failure] from the repository so [presentFailure] can
/// drive the UX. This entity only models the *pending* and *verified* states.
class VerificationResult extends Equatable {
  const VerificationResult({
    required this.kind,
    required this.status,
    this.verifiedName = '',
    this.verifiedDob = '',
    this.idMasked = '',
    this.referenceId = '',
  });

  final String kind; // pan | aadhaar | bank
  final String status; // verified | pending | failed
  final String verifiedName;
  final String verifiedDob;
  final String idMasked;
  final String referenceId; // OTP request id, provider trace, etc.

  bool get isVerified => status == 'verified';
  bool get isPending => status == 'pending';

  factory VerificationResult.fromJson(Map<String, dynamic> j) =>
      VerificationResult(
        kind: j['kind']?.toString() ?? '',
        status: j['status']?.toString() ?? '',
        verifiedName: j['verifiedName']?.toString() ?? '',
        verifiedDob: j['verifiedDob']?.toString() ?? '',
        idMasked: j['idMasked']?.toString() ?? '',
        referenceId: j['referenceId']?.toString() ?? '',
      );

  @override
  List<Object?> get props =>
      [kind, status, verifiedName, verifiedDob, idMasked, referenceId];
}
