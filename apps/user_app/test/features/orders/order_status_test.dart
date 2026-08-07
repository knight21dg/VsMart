import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/orders/domain/entities/order_enums.dart';

void main() {
  group('OrderStatusX classification', () {
    test('every backend status has a non-empty label (none collapse silently)', () {
      for (final s in OrderStatus.values) {
        expect(s.label.trim(), isNotEmpty, reason: 'missing label for $s');
      }
    });

    test('completed states', () {
      expect(OrderStatus.delivered.isCompleted, true);
      expect(OrderStatus.partiallyReturned.isCompleted, true);
      expect(OrderStatus.pending.isCompleted, false);
      expect(OrderStatus.cancelled.isCompleted, false);
    });

    test('cancelled/terminal-failure states', () {
      for (final s in [
        OrderStatus.cancelled, OrderStatus.rejected, OrderStatus.returned,
      ]) {
        expect(s.isCancelled, true, reason: '$s should count as cancelled');
      }
      expect(OrderStatus.delivered.isCancelled, false);
    });

    test('every status is EXACTLY one of active / completed / cancelled', () {
      for (final s in OrderStatus.values) {
        final trueCount =
            [s.isActive, s.isCompleted, s.isCancelled].where((f) => f).length;
        expect(trueCount, 1,
            reason: '$s → active=${s.isActive} completed=${s.isCompleted} '
                'cancelled=${s.isCancelled}');
      }
    });

    test('progress is bounded, 1.0 delivered, 0.0 cancelled', () {
      expect(OrderStatus.delivered.progress, 1.0);
      expect(OrderStatus.cancelled.progress, 0.0);
      for (final s in OrderStatus.values) {
        expect(s.progress, inInclusiveRange(0.0, 1.0), reason: '$s progress');
      }
    });
  });

  group('OrderStatusX.isCancellable (mirrors backend cancel guard)', () {
    test('only pending and confirmed are cancellable', () {
      expect(OrderStatus.pending.isCancellable, true);
      expect(OrderStatus.confirmed.isCancellable, true);
      // Regression: `packed` used to show a Cancel button the backend rejected.
      expect(OrderStatus.packed.isCancellable, false);
      expect(OrderStatus.outForDelivery.isCancellable, false);
      expect(OrderStatus.delivered.isCancellable, false);
    });
  });
}
