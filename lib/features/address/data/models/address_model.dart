import '../../domain/entities/address.dart';

/// JSON serialization bridging [Address] and the maps persisted to the Hive
/// `addressBox`.
abstract final class AddressModel {
  AddressModel._();

  static Map<String, dynamic> toJson(Address a) => {
        'id': a.id,
        'name': a.name,
        'phone': a.phone,
        'line1': a.line1,
        'village': a.village,
        'area': a.area,
        'district': a.district,
        'state': a.state,
        'pincode': a.pincode,
        'landmark': a.landmark,
        'latitude': a.latitude,
        'longitude': a.longitude,
        'isDefault': a.isDefault,
      };

  static Address fromJson(Map<String, dynamic> j) => Address(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        line1: j['line1'] as String? ?? '',
        village: j['village'] as String? ?? '',
        area: j['area'] as String? ?? '',
        district: j['district'] as String? ?? '',
        state: j['state'] as String? ?? '',
        pincode: j['pincode'] as String? ?? '',
        landmark: j['landmark'] as String? ?? '',
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        isDefault: j['isDefault'] as bool? ?? false,
      );
}
