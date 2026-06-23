import '../../domain/entities/order.dart';
import '../../domain/entities/order_enums.dart';
import '../../domain/entities/order_parts.dart';

/// JSON serialization for [Order] and its nested parts (Hive + future remote).
abstract final class OrderModel {
  OrderModel._();

  static Map<String, dynamic> toJson(Order o) => {
        'id': o.id,
        'items': o.items.map(_itemToJson).toList(),
        'address': _addressToJson(o.address),
        'payment': _paymentToJson(o.payment),
        'summary': _summaryToJson(o.summary),
        'status': o.status.name,
        'placedAt': o.placedAt.millisecondsSinceEpoch,
        'estimatedDelivery': o.estimatedDelivery?.millisecondsSinceEpoch,
        'timeline': o.timeline.map(_timelineToJson).toList(),
      };

  static Order fromJson(Map<String, dynamic> j) => Order(
        id: j['id'] as String? ?? '',
        items: (j['items'] as List?)
                ?.whereType<Map>()
                .map((e) => _itemFromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            const [],
        address: _addressFromJson(
            Map<String, dynamic>.from(j['address'] as Map? ?? {})),
        payment: _paymentFromJson(
            Map<String, dynamic>.from(j['payment'] as Map? ?? {})),
        summary: _summaryFromJson(
            Map<String, dynamic>.from(j['summary'] as Map? ?? {})),
        status: _enumByName(OrderStatus.values, j['status'] as String?) ??
            OrderStatus.pending,
        placedAt: DateTime.fromMillisecondsSinceEpoch(
            (j['placedAt'] as num?)?.toInt() ?? 0),
        estimatedDelivery: j['estimatedDelivery'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (j['estimatedDelivery'] as num).toInt()),
        timeline: (j['timeline'] as List?)
                ?.whereType<Map>()
                .map((e) => _timelineFromJson(Map<String, dynamic>.from(e)))
                .toList() ??
            const [],
      );

  // --- parts -------------------------------------------------------------

  static Map<String, dynamic> _itemToJson(OrderItem i) => {
        'productId': i.productId,
        'name': i.name,
        'brand': i.brand,
        'unit': i.unit,
        'price': i.price,
        'quantity': i.quantity,
        'mrp': i.mrp,
        'imageUrl': i.imageUrl,
      };

  static OrderItem _itemFromJson(Map<String, dynamic> j) => OrderItem(
        productId: j['productId'] as String? ?? '',
        name: j['name'] as String? ?? '',
        brand: j['brand'] as String? ?? '',
        unit: j['unit'] as String? ?? '',
        price: (j['price'] as num?) ?? 0,
        quantity: (j['quantity'] as num?)?.toInt() ?? 1,
        mrp: j['mrp'] as num?,
        imageUrl: j['imageUrl'] as String?,
      );

  static Map<String, dynamic> _addressToJson(OrderAddress a) => {
        'name': a.name,
        'phone': a.phone,
        'formatted': a.formatted,
        'pincode': a.pincode,
        'latitude': a.latitude,
        'longitude': a.longitude,
      };

  static OrderAddress _addressFromJson(Map<String, dynamic> j) => OrderAddress(
        name: j['name'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        formatted: j['formatted'] as String? ?? '',
        pincode: j['pincode'] as String? ?? '',
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
      );

  static Map<String, dynamic> _paymentToJson(OrderPayment p) => {
        'method': p.method.name,
        'status': p.status.name,
        'amount': p.amount,
        'creditUsed': p.creditUsed,
      };

  static OrderPayment _paymentFromJson(Map<String, dynamic> j) => OrderPayment(
        method: _enumByName(PaymentMethod.values, j['method'] as String?) ??
            PaymentMethod.cashOnDelivery,
        status: _enumByName(PaymentStatus.values, j['status'] as String?) ??
            PaymentStatus.pending,
        amount: (j['amount'] as num?) ?? 0,
        creditUsed: (j['creditUsed'] as num?) ?? 0,
      );

  static Map<String, dynamic> _summaryToJson(OrderSummary s) => {
        'itemTotal': s.itemTotal,
        'deliveryFee': s.deliveryFee,
        'grandTotal': s.grandTotal,
        'discount': s.discount,
        'creditUsed': s.creditUsed,
      };

  static OrderSummary _summaryFromJson(Map<String, dynamic> j) => OrderSummary(
        itemTotal: (j['itemTotal'] as num?) ?? 0,
        deliveryFee: (j['deliveryFee'] as num?) ?? 0,
        grandTotal: (j['grandTotal'] as num?) ?? 0,
        discount: (j['discount'] as num?) ?? 0,
        creditUsed: (j['creditUsed'] as num?) ?? 0,
      );

  static Map<String, dynamic> _timelineToJson(OrderTimelineEntry t) => {
        'status': t.status.name,
        'label': t.label,
        'at': t.at?.millisecondsSinceEpoch,
        'done': t.done,
      };

  static OrderTimelineEntry _timelineFromJson(Map<String, dynamic> j) =>
      OrderTimelineEntry(
        status: _enumByName(OrderStatus.values, j['status'] as String?) ??
            OrderStatus.pending,
        label: j['label'] as String? ?? '',
        at: j['at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()),
        done: j['done'] as bool? ?? false,
      );

  static T? _enumByName<T extends Enum>(List<T> values, String? name) {
    if (name == null) return null;
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}
