import 'package:equatable/equatable.dart';

/// A customer delivery address. Shared by registration, checkout, order
/// delivery, profile, and (later) agent verification & admin.
class Address extends Equatable {
  const Address({
    required this.id,
    required this.name,
    required this.phone,
    this.line1 = '',
    this.village = '',
    this.area = '',
    this.district = '',
    this.state = '',
    this.pincode = '',
    this.landmark = '',
    this.latitude,
    this.longitude,
    this.isDefault = false,
  });

  final String id;
  final String name;
  final String phone;
  final String line1;
  final String village;
  final String area;
  final String district;
  final String state;
  final String pincode;
  final String landmark;
  final double? latitude;
  final double? longitude;
  final bool isDefault;

  bool get hasCoordinates => latitude != null && longitude != null;

  /// Single-line, human-readable address.
  String get formatted => [
        line1,
        village,
        area,
        landmark,
        district,
        state,
        pincode,
      ].where((p) => p.trim().isNotEmpty).join(', ');

  Address copyWith({bool? isDefault}) => Address(
        id: id,
        name: name,
        phone: phone,
        line1: line1,
        village: village,
        area: area,
        district: district,
        state: state,
        pincode: pincode,
        landmark: landmark,
        latitude: latitude,
        longitude: longitude,
        isDefault: isDefault ?? this.isDefault,
      );

  @override
  List<Object?> get props => [
        id,
        name,
        phone,
        line1,
        village,
        area,
        district,
        state,
        pincode,
        landmark,
        latitude,
        longitude,
        isDefault,
      ];
}
