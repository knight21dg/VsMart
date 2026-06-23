import '../../domain/entities/verification_draft.dart';
import '../../domain/entities/verification_enums.dart';

/// JSON serialization for the locally-persisted [VerificationDraft] (Hive).
abstract final class VerificationDraftModel {
  VerificationDraftModel._();

  static Map<String, dynamic> toJson(VerificationDraft d) => {
        'aadhaarNumber': d.aadhaarNumber,
        'panNumber': d.panNumber,
        'aadhaarFrontPath': d.aadhaarFrontPath,
        'aadhaarBackPath': d.aadhaarBackPath,
        'panPath': d.panPath,
        'selfiePath': d.selfiePath,
        'occupation': d.occupation,
        'monthlyIncome': d.monthlyIncome,
        'familyMembers': d.familyMembers,
        'houseType': d.houseType?.name,
        'ownership': d.ownership?.name,
        'requestedLimit': d.requestedLimit,
        'status': d.status.name,
      };

  static VerificationDraft fromJson(Map<String, dynamic> j) => VerificationDraft(
        aadhaarNumber: j['aadhaarNumber'] as String? ?? '',
        panNumber: j['panNumber'] as String? ?? '',
        aadhaarFrontPath: j['aadhaarFrontPath'] as String?,
        aadhaarBackPath: j['aadhaarBackPath'] as String?,
        panPath: j['panPath'] as String?,
        selfiePath: j['selfiePath'] as String?,
        occupation: j['occupation'] as String? ?? '',
        monthlyIncome: j['monthlyIncome'] as num?,
        familyMembers: (j['familyMembers'] as num?)?.toInt(),
        houseType: _enumByName(HouseType.values, j['houseType'] as String?),
        ownership: _enumByName(Ownership.values, j['ownership'] as String?),
        requestedLimit: j['requestedLimit'] as num?,
        status: _enumByName(VerificationStatus.values, j['status'] as String?) ??
            VerificationStatus.draft,
      );

  static T? _enumByName<T extends Enum>(List<T> values, String? name) {
    if (name == null) return null;
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}
