import 'package:equatable/equatable.dart';

import 'order_enums.dart';
import 'order_parts.dart';

/// The order aggregate: items, address, payment, billing, status and timeline.
class Order extends Equatable {
  const Order({
    required this.id,
    required this.items,
    required this.address,
    required this.payment,
    required this.summary,
    required this.status,
    required this.placedAt,
    this.estimatedDelivery,
    this.timeline = const [],
  });

  final String id;
  final List<OrderItem> items;
  final OrderAddress address;
  final OrderPayment payment;
  final OrderSummary summary;
  final OrderStatus status;
  final DateTime placedAt;
  final DateTime? estimatedDelivery;
  final List<OrderTimelineEntry> timeline;

  int get itemCount => items.fold(0, (sum, i) => sum + i.quantity);

  Order copyWith({OrderStatus? status, List<OrderTimelineEntry>? timeline}) =>
      Order(
        id: id,
        items: items,
        address: address,
        payment: payment,
        summary: summary,
        status: status ?? this.status,
        placedAt: placedAt,
        estimatedDelivery: estimatedDelivery,
        timeline: timeline ?? this.timeline,
      );

  @override
  List<Object?> get props => [
        id,
        items,
        address,
        payment,
        summary,
        status,
        placedAt,
        estimatedDelivery,
        timeline,
      ];
}
