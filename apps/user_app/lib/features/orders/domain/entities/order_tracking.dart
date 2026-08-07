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
    this.agentPhotoUrl,
    this.etaLabel,
    this.agentLat,
    this.agentLng,
    this.storeLat,
    this.storeLng,
    this.destLat,
    this.destLng,
    this.hasLiveLocation = false,
    this.deliveryOtp = '',
  });

  final String orderId;
  final OrderStatus currentStatus;
  final List<OrderTimelineEntry> timeline;
  final String? agentName;
  final String? agentPhone;
  final String? agentPhotoUrl;
  final String? etaLabel;

  /// True when the backend gave us a number to actually dial the rider.
  bool get canCallAgent => (agentPhone ?? '').isNotEmpty;

  /// Live agent coordinates streamed by the backend (null until assigned).
  final double? agentLat;
  final double? agentLng;

  /// The trip endpoints: the serving store (pickup) and the delivery address.
  /// Drive the real store → destination route on the tracking map.
  final double? storeLat;
  final double? storeLng;
  final double? destLat;
  final double? destLng;

  bool get hasStore => storeLat != null && storeLng != null;
  bool get hasDestination => destLat != null && destLng != null;

  /// True when the backend is streaming the agent's live coordinates.
  final bool hasLiveLocation;

  /// The handover code the customer reads to the rider at the door. Non-empty
  /// ONLY while a rider is out with the parcel and the code is still usable —
  /// the backend clears it after verification or lockout.
  final String deliveryOtp;

  bool get hasDeliveryOtp => deliveryOtp.isNotEmpty;

  @override
  List<Object?> get props => [
        orderId,
        currentStatus,
        timeline,
        agentName,
        agentPhone,
        agentPhotoUrl,
        etaLabel,
        agentLat,
        agentLng,
        storeLat,
        storeLng,
        destLat,
        destLng,
        hasLiveLocation,
        deliveryOtp,
      ];
}
