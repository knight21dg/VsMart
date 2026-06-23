import '../../../app/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import 'serviceability_result.dart';

/// Talks to the public serviceability endpoints. Auth-optional on the backend,
/// so this uses [ApiClient.noAuth] and can run pre-login (e.g. at app launch).
class ServiceabilityDataSource {
  ServiceabilityDataSource(this._client);

  final ApiClient _client;

  Map<String, dynamic> _obj(dynamic raw) {
    final data = raw is Map && raw['data'] is Map ? raw['data'] : raw;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// Resolve serviceability for a coordinate (preferred) and/or pincode.
  Future<ServiceabilityResult> check({
    double? latitude,
    double? longitude,
    String? pincode,
  }) async {
    final query = <String, dynamic>{
      if (latitude != null) 'lat': latitude,
      if (longitude != null) 'lng': longitude,
      if (pincode != null && pincode.isNotEmpty) 'pincode': pincode,
    };
    final res = await _client.get<dynamic>(
      ApiConstants.serviceabilityCheck,
      query: query,
      options: ApiClient.noAuth(),
    );
    return ServiceabilityResult.fromJson(_obj(res.data));
  }

  /// Capture a "not available in your area yet" lead for future expansion.
  Future<void> requestExpansion({
    required String name,
    required String mobile,
    String village = '',
    String area = '',
    String pincode = '',
    double? latitude,
    double? longitude,
  }) async {
    await _client.post<dynamic>(
      ApiConstants.expansionRequest,
      data: {
        'name': name,
        'mobile': mobile,
        'village': village,
        'area': area,
        'pincode': pincode,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
      },
      options: ApiClient.noAuth(),
    );
  }
}
