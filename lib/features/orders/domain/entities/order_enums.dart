/// Lifecycle states of an order. Mirrors the backend `OrderStatus` choices
/// (orders/models.py) so every server status renders correctly — no value
/// silently collapses to "Pending".
enum OrderStatus {
  draft,
  pending,
  placed,
  confirmed,
  packed,
  readyForDispatch,
  outForDelivery,
  delivered,
  cancelled,
  rejected,
  returned,
  partiallyReturned,
  failedDelivery,
}

extension OrderStatusX on OrderStatus {
  String get label => switch (this) {
        OrderStatus.draft => 'Draft',
        OrderStatus.pending => 'Pending',
        OrderStatus.placed => 'Placed',
        OrderStatus.confirmed => 'Confirmed',
        OrderStatus.packed => 'Packed',
        OrderStatus.readyForDispatch => 'Ready for Dispatch',
        OrderStatus.outForDelivery => 'Out for Delivery',
        OrderStatus.delivered => 'Delivered',
        OrderStatus.cancelled => 'Cancelled',
        OrderStatus.rejected => 'Rejected',
        OrderStatus.returned => 'Returned',
        OrderStatus.partiallyReturned => 'Partially Returned',
        OrderStatus.failedDelivery => 'Delivery Failed',
      };

  /// A delivered order (fully or partially returned afterwards still counts as
  /// a completed delivery).
  bool get isCompleted =>
      this == OrderStatus.delivered || this == OrderStatus.partiallyReturned;

  /// Terminal failure states.
  bool get isCancelled =>
      this == OrderStatus.cancelled ||
      this == OrderStatus.rejected ||
      this == OrderStatus.returned;

  /// Anything still in flight (incl. a failed-delivery awaiting re-attempt and
  /// drafts the server may surface). Defined as "neither done nor cancelled" so
  /// no status is ever hidden from the active list.
  bool get isActive => !isCompleted && !isCancelled;

  /// Forward progress (0..1) along the standard delivery flow.
  double get progress => switch (this) {
        OrderStatus.draft => 0.05,
        OrderStatus.pending => 0.1,
        OrderStatus.placed => 0.18,
        OrderStatus.confirmed => 0.3,
        OrderStatus.packed => 0.5,
        OrderStatus.readyForDispatch => 0.65,
        OrderStatus.outForDelivery => 0.8,
        OrderStatus.failedDelivery => 0.8,
        OrderStatus.delivered => 1.0,
        OrderStatus.partiallyReturned => 1.0,
        OrderStatus.cancelled => 0.0,
        OrderStatus.rejected => 0.0,
        OrderStatus.returned => 0.0,
      };
}

/// How an order is paid for.
enum PaymentMethod { credit, cashOnDelivery, upi, card }

extension PaymentMethodX on PaymentMethod {
  String get label => switch (this) {
        PaymentMethod.credit => 'VS Credit',
        PaymentMethod.cashOnDelivery => 'Cash on Delivery',
        PaymentMethod.upi => 'UPI',
        PaymentMethod.card => 'Card',
      };
}

/// Settlement state of an order's payment.
enum PaymentStatus { pending, paid, failed, refunded }

extension PaymentStatusX on PaymentStatus {
  String get label => switch (this) {
        PaymentStatus.pending => 'Pending',
        PaymentStatus.paid => 'Paid',
        PaymentStatus.failed => 'Failed',
        PaymentStatus.refunded => 'Refunded',
      };
}
