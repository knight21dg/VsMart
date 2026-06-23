import 'package:equatable/equatable.dart';

import 'order_enums.dart';

/// A line item captured at order time (snapshot — independent of the live cart).
class OrderItem extends Equatable {
  const OrderItem({
    required this.productId,
    required this.name,
    required this.brand,
    required this.unit,
    required this.price,
    required this.quantity,
    this.mrp,
    this.imageUrl,
  });

  final String productId;
  final String name;
  final String brand;
  final String unit;
  final num price;
  final int quantity;
  final num? mrp;
  final String? imageUrl;

  num get lineTotal => price * quantity;

  @override
  List<Object?> get props =>
      [productId, name, brand, unit, price, quantity, mrp, imageUrl];
}

/// A snapshot of the delivery address at order time.
class OrderAddress extends Equatable {
  const OrderAddress({
    required this.name,
    required this.phone,
    required this.formatted,
    this.pincode = '',
    this.latitude,
    this.longitude,
  });

  final String name;
  final String phone;
  final String formatted;
  final String pincode;
  final double? latitude;
  final double? longitude;

  @override
  List<Object?> get props =>
      [name, phone, formatted, pincode, latitude, longitude];
}

/// Payment details for an order.
class OrderPayment extends Equatable {
  const OrderPayment({
    required this.method,
    required this.status,
    required this.amount,
    this.creditUsed = 0,
  });

  final PaymentMethod method;
  final PaymentStatus status;
  final num amount;
  final num creditUsed;

  bool get usedCredit => creditUsed > 0;

  @override
  List<Object?> get props => [method, status, amount, creditUsed];
}

/// Billing breakdown for an order.
class OrderSummary extends Equatable {
  const OrderSummary({
    required this.itemTotal,
    required this.deliveryFee,
    required this.grandTotal,
    this.discount = 0,
    this.creditUsed = 0,
  });

  final num itemTotal;
  final num deliveryFee;
  final num grandTotal;
  final num discount;
  final num creditUsed;

  @override
  List<Object?> get props =>
      [itemTotal, deliveryFee, grandTotal, discount, creditUsed];
}

/// A single node in an order's progress timeline.
class OrderTimelineEntry extends Equatable {
  const OrderTimelineEntry({
    required this.status,
    required this.label,
    this.at,
    this.done = false,
  });

  final OrderStatus status;
  final String label;
  final DateTime? at;
  final bool done;

  @override
  List<Object?> get props => [status, label, at, done];
}
