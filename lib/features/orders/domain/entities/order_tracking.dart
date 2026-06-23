import 'package:equatable/equatable.dart';

import 'order_enums.dart';
import 'order_parts.dart';

/// Live tracking view of an order: its current status, the progress timeline,
/// and (when out for delivery) the assigned agent and ETA.
class OrderTracking extends Equatable {
  const OrderTracking({
    required this.orderId,
    required this.currentStatus,
    required this.timeline,
    this.agentName,
    this.agentPhone,
    this.etaLabel,
    this.agentLat,
    this.agentLng,
    this.hasLiveLocation = false,
  });

  final String orderId;
  final OrderStatus currentStatus;
  final List<OrderTimelineEntry> timeline;
  final String? agentName;
  final String? agentPhone;
  final String? etaLabel;

  /// Live agent coordinates streamed by the backend (null until assigned).
  final double? agentLat;
  final double? agentLng;

  /// True when the backend is streaming the agent's live coordinates.
  final bool hasLiveLocation;

  @override
  List<Object?> get props => [
        orderId,
        currentStatus,
        timeline,
        agentName,
        agentPhone,
        etaLabel,
        agentLat,
        agentLng,
        hasLiveLocation,
      ];
}
