import '../../../../app/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/address.dart';

/// Backend address API (`/api/v1/addresses`). Maps the [Address] entity to/from
/// the backend contract and unwraps the `{success,message,data}` envelope.
class AddressRemoteDataSource {
  AddressRemoteDataSource(this._client);

  final ApiClient _client;

  List<Map<String, dynamic>> _list(dynamic raw) {
    final data = raw is Map ? raw['data'] : raw;
    final list = data is List ? data : const [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Map<String, dynamic> _obj(dynamic raw) {
    final data = raw is Map && raw['data'] is Map ? raw['data'] : raw;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  Future<List<Address>> list() async {
    final r = await _client.get<dynamic>(ApiConstants.addresses);
    return _list(r.data).map(_toEntity).toList();
  }

  Future<Address> create(Address a) async {
    final r = await _client.post<dynamic>(ApiConstants.addresses, data: _toBody(a));
    return _toEntity(_obj(r.data));
  }

  Future<Address> update(Address a) async {
    final r = await _client.patch<dynamic>(
      ApiConstants.address(a.id), data: _toBody(a),
    );
    return _toEntity(_obj(r.data));
  }

  Future<void> delete(String id) => _client.delete<dynamic>(ApiConstants.address(id));

  Future<void> setDefault(String id) =>
      _client.post<dynamic>('${ApiConstants.address(id)}/default');

  Map<String, dynamic> _toBody(Address a) => {
        'name': a.name,
        'phone': a.phone,
        'line1': a.line1,
        'village': a.village,
        'area': a.area,
        'landmark': a.landmark,
        'district': a.district,
        'state': a.state,
        'pincode': a.pincode,
        if (a.latitude != null) 'latitude': a.latitude,
        if (a.longitude != null) 'longitude': a.longitude,
        'is_default': a.isDefault,
      };

  Address _toEntity(Map<String, dynamic> j) => Address(
        id: j['id'].toString(),
        name: (j['name'] ?? '').toString(),
        phone: (j['phone'] ?? '').toString(),
        line1: (j['line1'] ?? '').toString(),
        village: (j['village'] ?? '').toString(),
        area: (j['area'] ?? '').toString(),
        district: (j['district'] ?? j['city'] ?? '').toString(),
        state: (j['state'] ?? '').toString(),
        pincode: (j['pincode'] ?? '').toString(),
        landmark: (j['landmark'] ?? '').toString(),
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        isDefault: j['isDefault'] as bool? ?? false,
      );
}
