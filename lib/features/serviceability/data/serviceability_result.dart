import 'package:equatable/equatable.dart';

/// Result of a serviceability check (`/serviceability/check`). Mirrors the
/// backend contract: a customer point resolves to a serving zone + store, or to
/// "not serviceable" when it falls outside every zone polygon.
class ServiceabilityResult extends Equatable {
  const ServiceabilityResult({
    required this.serviceable,
    this.zoneId,
    this.zoneName,
    this.storeId,
    this.storeName,
    this.deliveryFee,
    this.minimumOrder,
    this.creditAvailable = false,
    this.estimatedDeliveryMinutes,
    this.freeDeliveryThreshold,
  });

  final bool serviceable;
  final String? zoneId;
  final String? zoneName;
  final String? storeId;
  final String? storeName;
  final double? deliveryFee;
  final double? minimumOrder;
  final bool creditAvailable;
  final int? estimatedDeliveryMinutes;
  final double? freeDeliveryThreshold;

  /// The default "we haven't resolved a location yet / outside coverage" value.
  static const unknown = ServiceabilityResult(serviceable: false);

  static double? _toD(dynamic v) =>
      v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

  static int? _toI(dynamic v) =>
      v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));

  factory ServiceabilityResult.fromJson(Map<String, dynamic> j) =>
      ServiceabilityResult(
        serviceable: j['serviceable'] == true,
        zoneId: j['zoneId']?.toString(),
        zoneName: j['zoneName']?.toString(),
        storeId: j['storeId']?.toString(),
        storeName: j['storeName']?.toString(),
        deliveryFee: _toD(j['deliveryFee']),
        minimumOrder: _toD(j['minimumOrder']),
        creditAvailable: j['creditAvailable'] == true,
        estimatedDeliveryMinutes: _toI(j['estimatedDeliveryTime']),
        freeDeliveryThreshold: _toD(j['freeDeliveryThreshold']),
      );

  Map<String, dynamic> toJson() => {
        'serviceable': serviceable,
        'zoneId': zoneId,
        'zoneName': zoneName,
        'storeId': storeId,
        'storeName': storeName,
        'deliveryFee': deliveryFee,
        'minimumOrder': minimumOrder,
        'creditAvailable': creditAvailable,
        'estimatedDeliveryTime': estimatedDeliveryMinutes,
        'freeDeliveryThreshold': freeDeliveryThreshold,
      };

  @override
  List<Object?> get props => [
        serviceable,
        zoneId,
        storeId,
        deliveryFee,
        minimumOrder,
        creditAvailable,
        estimatedDeliveryMinutes,
      ];
}
