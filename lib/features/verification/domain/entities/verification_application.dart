import 'package:equatable/equatable.dart';

import 'verification_enums.dart';

/// The submitted verification application as tracked by the backend: an id, the
/// current [status], and review metadata.
class VerificationApplication extends Equatable {
  const VerificationApplication({
    required this.applicationId,
    required this.status,
    required this.submittedAt,
    this.expectedReviewDays = 2,
    this.approvedLimit,
    this.rejectionReason,
  });

  final String applicationId;
  final VerificationStatus status;
  final DateTime submittedAt;
  final int expectedReviewDays;
  final num? approvedLimit;
  final String? rejectionReason;

  @override
  List<Object?> get props => [
        applicationId,
        status,
        submittedAt,
        expectedReviewDays,
        approvedLimit,
        rejectionReason,
      ];
}
