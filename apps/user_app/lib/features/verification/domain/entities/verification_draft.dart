import 'package:equatable/equatable.dart';

import 'verification_enums.dart';

/// The resumable verification application draft. A single aggregate the customer
/// fills across Identity → Selfie → Credit steps; persisted locally after every
/// change so progress survives app kills and offline gaps.
class VerificationDraft extends Equatable {
  const VerificationDraft({
    this.aadhaarNumber = '',
    this.panNumber = '',
    this.aadhaarFrontPath,
    this.aadhaarBackPath,
    this.panPath,
    this.selfiePath,
    this.residencePhotoPath,
    this.residenceLatitude,
    this.residenceLongitude,
    this.occupation = '',
    this.monthlyIncome,
    this.familyMembers,
    this.houseType,
    this.ownership,
    this.requestedLimit,
    this.status = VerificationStatus.draft,
  });

  // Identity
  final String aadhaarNumber;
  final String panNumber;
  final String? aadhaarFrontPath;
  final String? aadhaarBackPath;
  final String? panPath;

  // Selfie
  final String? selfiePath;

  // Residence (home photo + real device GPS captured on the residence step)
  final String? residencePhotoPath;
  final double? residenceLatitude;
  final double? residenceLongitude;

  // Credit application
  final String occupation;
  final num? monthlyIncome;
  final int? familyMembers;
  final HouseType? houseType;
  final Ownership? ownership;
  final num? requestedLimit;

  final VerificationStatus status;

  bool get isIdentityComplete =>
      aadhaarNumber.isNotEmpty &&
      panNumber.isNotEmpty &&
      aadhaarFrontPath != null &&
      aadhaarBackPath != null &&
      panPath != null;

  bool get isSelfieComplete => selfiePath != null;

  bool get isResidenceComplete =>
      residencePhotoPath != null &&
      residenceLatitude != null &&
      residenceLongitude != null;

  bool get isCreditComplete =>
      occupation.isNotEmpty &&
      monthlyIncome != null &&
      familyMembers != null &&
      houseType != null &&
      ownership != null &&
      requestedLimit != null;

  /// KYC is an **identity** submission: Aadhaar + PAN + selfie + residence.
  ///
  /// It deliberately does NOT require [isCreditComplete]. Requiring it meant a
  /// customer who only wanted to verify their identity could never submit —
  /// the Submit button stayed disabled until they had also filled in a credit
  /// application. Applying for credit is its own flow (`POST /credit/apply`)
  /// and its own decision; see the backend's KYC/credit decoupling.
  bool get isReadyToSubmit =>
      isIdentityComplete && isSelfieComplete && isResidenceComplete;

  VerificationDraft copyWith({
    String? aadhaarNumber,
    String? panNumber,
    String? aadhaarFrontPath,
    String? aadhaarBackPath,
    String? panPath,
    String? selfiePath,
    String? residencePhotoPath,
    double? residenceLatitude,
    double? residenceLongitude,
    String? occupation,
    num? monthlyIncome,
    int? familyMembers,
    HouseType? houseType,
    Ownership? ownership,
    num? requestedLimit,
    VerificationStatus? status,
  }) {
    return VerificationDraft(
      aadhaarNumber: aadhaarNumber ?? this.aadhaarNumber,
      panNumber: panNumber ?? this.panNumber,
      aadhaarFrontPath: aadhaarFrontPath ?? this.aadhaarFrontPath,
      aadhaarBackPath: aadhaarBackPath ?? this.aadhaarBackPath,
      panPath: panPath ?? this.panPath,
      selfiePath: selfiePath ?? this.selfiePath,
      residencePhotoPath: residencePhotoPath ?? this.residencePhotoPath,
      residenceLatitude: residenceLatitude ?? this.residenceLatitude,
      residenceLongitude: residenceLongitude ?? this.residenceLongitude,
      occupation: occupation ?? this.occupation,
      monthlyIncome: monthlyIncome ?? this.monthlyIncome,
      familyMembers: familyMembers ?? this.familyMembers,
      houseType: houseType ?? this.houseType,
      ownership: ownership ?? this.ownership,
      requestedLimit: requestedLimit ?? this.requestedLimit,
      status: status ?? this.status,
    );
  }

  @override
  List<Object?> get props => [
        aadhaarNumber,
        panNumber,
        aadhaarFrontPath,
        aadhaarBackPath,
        panPath,
        selfiePath,
        residencePhotoPath,
        residenceLatitude,
        residenceLongitude,
        occupation,
        monthlyIncome,
        familyMembers,
        houseType,
        ownership,
        requestedLimit,
        status,
      ];
}
