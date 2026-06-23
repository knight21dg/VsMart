import '../../../app/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import 'app_status.dart';

/// Talks to the backend `system` endpoints (under `/api/v1`): `/app-config` is
/// public, so this uses [ApiClient.noAuth] and can run pre-login.
class SystemRemoteDataSource {
  SystemRemoteDataSource(this._client);

  final ApiClient _client;

  Map<String, dynamic> _obj(dynamic raw) {
    final data = raw is Map && raw['data'] is Map ? raw['data'] : raw;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<AppStatus> getAppConfig() async {
    final res = await _client.get<dynamic>(
      ApiConstants.appConfig,
      options: ApiClient.noAuth(),
    );
    final j = _obj(res.data);
    final flags = <String, bool>{};
    final rawFlags = j['featureFlags'];
    if (rawFlags is Map) {
      rawFlags.forEach((k, v) {
        if (v is bool) flags[k.toString()] = v;
      });
    }
    return AppStatus(
      minAppVersion: (j['minAppVersion'] ?? '0.0.0').toString(),
      maintenance: j['maintenance'] as bool? ?? false,
      featureFlags: flags,
      supportPhone: j['supportPhone'] as String?,
      supportEmail: j['supportEmail'] as String?,
    );
  }
}
