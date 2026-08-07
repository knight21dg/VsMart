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
    this.storePhone,
    this.deliveryFee,
    this.minimumOrder,
    this.creditAvailable = false,
    this.estimatedDeliveryMinutes,
    this.freeDeliveryThreshold,
    this.storeOpen,
    this.opensAt,
    this.closesAt,
    this.acceptingOrders,
    this.capacityReached,
  });

  final bool serviceable;
  final String? zoneId;
  final String? zoneName;
  final String? storeId;
  final String? storeName;

  /// The serving store's own phone number — Help & Support dials this
  /// directly when it's set, so a call reaches the actual store handling
  /// this customer's orders, not just a generic line.
  final String? storePhone;
  final double? deliveryFee;
  final double? minimumOrder;
  final bool creditAvailable;
  final int? estimatedDeliveryMinutes;
  final double? freeDeliveryThreshold;

  /// Store availability — the catalog stays visible, but checkout should be
  /// disabled (with a reason) when the serving store can't currently take orders.
  /// Null when not serviceable / unknown.
  final bool? storeOpen;
  final String? opensAt; // "HH:MM"
  final String? closesAt; // "HH:MM"
  final bool? acceptingOrders;
  final bool? capacityReached;

  /// Whether the customer can place an order right now: serviceable, the store is
  /// open, and today's delivery capacity isn't full. Drives the checkout button.
  bool get canCheckout =>
      serviceable && storeOpen != false && capacityReached != true;

  /// A human reason checkout is blocked, or null when it's allowed.
  String? get blockedReason {
    if (!serviceable) return "We don't deliver to your area yet.";
    if (capacityReached == true) return "Today's delivery slots are full.";
    if (storeOpen == false) {
      return opensAt != null
          ? 'Store is closed. Orders resume at $opensAt.'
          : 'Store is currently closed.';
    }
    return null;
  }

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
        storePhone: j['storePhone']?.toString(),
        deliveryFee: _toD(j['deliveryFee']),
        minimumOrder: _toD(j['minimumOrder']),
        creditAvailable: j['creditAvailable'] == true,
        estimatedDeliveryMinutes: _toI(j['estimatedDeliveryTime']),
        freeDeliveryThreshold: _toD(j['freeDeliveryThreshold']),
        storeOpen: j['storeOpen'] is bool ? j['storeOpen'] as bool : null,
        opensAt: j['opensAt']?.toString(),
        closesAt: j['closesAt']?.toString(),
        acceptingOrders:
            j['acceptingOrders'] is bool ? j['acceptingOrders'] as bool : null,
        capacityReached:
            j['capacityReached'] is bool ? j['capacityReached'] as bool : null,
      );

  Map<String, dynamic> toJson() => {
        'serviceable': serviceable,
        'zoneId': zoneId,
        'zoneName': zoneName,
        'storeId': storeId,
        'storeName': storeName,
        'storePhone': storePhone,
        'deliveryFee': deliveryFee,
        'minimumOrder': minimumOrder,
        'creditAvailable': creditAvailable,
        'estimatedDeliveryTime': estimatedDeliveryMinutes,
        'freeDeliveryThreshold': freeDeliveryThreshold,
        'storeOpen': storeOpen,
        'opensAt': opensAt,
        'closesAt': closesAt,
        'acceptingOrders': acceptingOrders,
        'capacityReached': capacityReached,
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
