import 'package:equatable/equatable.dart';

/// Lifecycle of a VS Credit application. Mirrors `credit.CreditApplication.Status`.
enum CreditApplicationStatus {
  draft,
  submitted,
  underReview('under_review'),
  approved,
  rejected,
  withdrawn;

  const CreditApplicationStatus([this.wire = '']);

  /// Server key when it differs from the Dart name (snake_case).
  final String wire;

  String get key => wire.isEmpty ? name : wire;

  static CreditApplicationStatus parse(String? v) =>
      CreditApplicationStatus.values.firstWhere(
        (s) => s.key == v,
        orElse: () => CreditApplicationStatus.draft,
      );

  /// A decision is pending — the customer should wait, not re-apply.
  bool get isInFlight =>
      this == CreditApplicationStatus.submitted ||
      this == CreditApplicationStatus.underReview;

  /// The customer may (re)apply from here.
  bool get canApply =>
      this == CreditApplicationStatus.draft ||
      this == CreditApplicationStatus.rejected ||
      this == CreditApplicationStatus.withdrawn;
}

/// The customer's credit application and its decision.
///
/// Note this carries no internal reviewer note — the server never sends one to
/// the applicant. [rejectionReason] is the customer-facing text.
class CreditApplication extends Equatable {
  const CreditApplication({
    required this.id,
    required this.status,
    this.occupation = '',
    this.monthlyIncome,
    this.familyMembers,
    this.houseType = '',
    this.ownership = '',
    this.requestedLimit,
    this.approvedLimit,
    this.rejectionReason = '',
    this.submittedAt,
    this.decidedAt,
  });

  final String id;
  final CreditApplicationStatus status;
  final String occupation;
  final num? monthlyIncome;
  final int? familyMembers;
  final String houseType;
  final String ownership;
  final num? requestedLimit;

  /// The sanctioned limit. Non-null only once approved.
  final num? approvedLimit;

  /// Customer-facing rejection text, shown verbatim.
  final String rejectionReason;

  final DateTime? submittedAt;
  final DateTime? decidedAt;

  factory CreditApplication.fromJson(Map<String, dynamic> j) {
    DateTime? date(dynamic v) =>
        v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
    return CreditApplication(
      id: (j['id'] ?? '').toString(),
      status: CreditApplicationStatus.parse(j['status']?.toString()),
      occupation: (j['occupation'] ?? '').toString(),
      monthlyIncome: _num(j['monthlyIncome'] ?? j['monthly_income']),
      familyMembers:
          _num(j['familyMembers'] ?? j['family_members'])?.toInt(),
      houseType: (j['houseType'] ?? j['house_type'] ?? '').toString(),
      ownership: (j['ownership'] ?? '').toString(),
      requestedLimit: _num(j['requestedLimit'] ?? j['requested_limit']),
      approvedLimit: _num(j['approvedLimit'] ?? j['approved_limit']),
      rejectionReason:
          (j['rejectionReason'] ?? j['rejection_reason'] ?? '').toString(),
      submittedAt: date(j['submittedAt'] ?? j['submitted_at']),
      decidedAt: date(j['decidedAt'] ?? j['decided_at']),
    );
  }

  /// Decimals arrive as strings from DRF — parse both shapes.
  static num? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  @override
  List<Object?> get props => [
        id,
        status,
        occupation,
        monthlyIncome,
        familyMembers,
        houseType,
        ownership,
        requestedLimit,
        approvedLimit,
        rejectionReason,
        submittedAt,
        decidedAt,
      ];
}
