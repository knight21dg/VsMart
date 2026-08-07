import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/orders/domain/entities/order_enums.dart';

/// Tracking must only be offered while the parcel is genuinely with a rider.
///
/// Every guard in the app used [OrderStatus.isActive] as the proxy for "can be
/// tracked", but that is true for `draft`, `pending`, `placed` and
/// `failedDelivery` — so an order placed thirty seconds ago opened a full-screen
/// map with a locally-simulated rider driving toward the customer, and a failed
/// delivery kept one open.
void main() {
  group('isTrackable', () {
    test('is true only once the store has handed the parcel over', () {
      expect(OrderStatus.readyForDispatch.isTrackable, isTrue);
      expect(OrderStatus.outForDelivery.isTrackable, isTrue);
    });

    test('is false while the order is still being prepared', () {
      for (final s in [
        OrderStatus.draft,
        OrderStatus.pending,
        OrderStatus.placed,
        OrderStatus.confirmed,
        OrderStatus.packed,
      ]) {
        expect(s.isTrackable, isFalse, reason: '$s');
      }
    });

    test('is false for every finished order', () {
      for (final s in [
        OrderStatus.delivered,
        OrderStatus.partiallyReturned,
        OrderStatus.cancelled,
        OrderStatus.rejected,
        OrderStatus.returned,
        OrderStatus.failedDelivery,
      ]) {
        expect(s.isTrackable, isFalse, reason: '$s');
      }
    });
  });

  group('isDispatched — gates the rider row and the call button', () {
    test('only out for delivery', () {
      expect(OrderStatus.outForDelivery.isDispatched, isTrue);
      // Ready for dispatch shows the map, but nobody is carrying it yet, so
      // there is no rider to phone.
      expect(OrderStatus.readyForDispatch.isDispatched, isFalse);
      expect(OrderStatus.packed.isDispatched, isFalse);
      expect(OrderStatus.delivered.isDispatched, isFalse);
    });
  });

  group('isFailed / isCompleted — these redirect to order details', () {
    test('a delivered or partially returned order is completed', () {
      expect(OrderStatus.delivered.isCompleted, isTrue);
      expect(OrderStatus.partiallyReturned.isCompleted, isTrue);
    });

    test('cancelled, rejected, returned and failed delivery are failures', () {
      for (final s in [
        OrderStatus.cancelled,
        OrderStatus.rejected,
        OrderStatus.returned,
        OrderStatus.failedDelivery,
      ]) {
        expect(s.isFailed, isTrue, reason: '$s');
      }
    });

    test('an in-flight order is neither', () {
      for (final s in [
        OrderStatus.confirmed,
        OrderStatus.packed,
        OrderStatus.outForDelivery,
      ]) {
        expect(s.isCompleted || s.isFailed, isFalse, reason: '$s');
      }
    });
  });

  group('isPreparing — drives the poll and the pre-dispatch backdrop', () {
    test('covers everything before hand-off', () {
      expect(OrderStatus.pending.isPreparing, isTrue);
      expect(OrderStatus.confirmed.isPreparing, isTrue);
      expect(OrderStatus.packed.isPreparing, isTrue);
    });

    test('stops once dispatched or finished', () {
      expect(OrderStatus.outForDelivery.isPreparing, isFalse);
      expect(OrderStatus.delivered.isPreparing, isFalse);
      // The poll used to run forever here: isActive is true for failedDelivery.
      expect(OrderStatus.failedDelivery.isPreparing, isFalse);
      expect(OrderStatus.failedDelivery.isTrackable, isFalse);
    });
  });
}
