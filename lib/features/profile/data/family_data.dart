import 'package:equatable/equatable.dart';

import '../../../app/constants/api_constants.dart';
import '../../../core/network/api_client.dart';

/// A household member sharing the primary account holder's credit line.
class FamilyMemberModel extends Equatable {
  const FamilyMemberModel({
    required this.id,
    required this.phone,
    required this.relationship,
    required this.status,
    this.sharedUsage = 0,
  });

  final String id;
  final String phone;
  final String relationship;

  /// `active` | `pending` | `removed`.
  final String status;
  final num sharedUsage;

  @override
  List<Object?> get props => [id, phone, relationship, status, sharedUsage];
}

/// The primary user's family group and its members, from `GET /credit/family`.
class FamilyGroupModel extends Equatable {
  const FamilyGroupModel({required this.sharedLimit, required this.members});

  final num sharedLimit;
  final List<FamilyMemberModel> members;

  @override
  List<Object?> get props => [sharedLimit, members];
}

/// Backend family-group API: `/credit/family`, `/credit/family/members/{id}`.
class FamilyRemoteDataSource {
  FamilyRemoteDataSource(this._client);

  final ApiClient _client;

  Map<String, dynamic> _obj(dynamic raw) {
    final data = raw is Map && raw['data'] is Map ? raw['data'] : raw;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  num _num(dynamic v) => v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;

  FamilyGroupModel _toGroup(Map<String, dynamic> j) => FamilyGroupModel(
        sharedLimit: _num(j['sharedLimit']),
        members: ((j['members'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => FamilyMemberModel(
                  id: (m['id'] ?? '').toString(),
                  phone: (m['phone'] ?? '').toString(),
                  relationship: (m['relationship'] ?? '').toString(),
                  status: (m['status'] ?? 'pending').toString(),
                  sharedUsage: _num(m['sharedUsage']),
                ))
            .where((m) => m.status != 'removed')
            .toList(),
      );

  Future<FamilyGroupModel> getFamily() async {
    final res = await _client.get<dynamic>(ApiConstants.creditFamily);
    return _toGroup(_obj(res.data));
  }

  Future<FamilyGroupModel> addMember({
    required String phone,
    required String relationship,
  }) async {
    final res = await _client.post<dynamic>(
      ApiConstants.creditFamily,
      data: {'phone': phone, 'relationship': relationship},
    );
    return _toGroup(_obj(res.data));
  }

  Future<void> removeMember(String id) =>
      _client.delete<dynamic>(ApiConstants.creditFamilyMember(id));
}
