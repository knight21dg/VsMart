import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/core/services/push_controller.dart';

/// A foreground push must refresh the data it is ABOUT.
///
/// `onMessage` only drew a local banner: "Order Out For Delivery" appeared
/// while the order screen underneath still read "Confirmed", and stayed wrong
/// until a pull-to-refresh or a navigation. The tracking screen's own 12s poll
/// masked that there, and nowhere else.
///
/// [pushOrderCode] is the whole decision — which order (if any) a push
/// invalidates. It has to stay targeted: a blanket refresh on every push would
/// re-download the catalog on a promo message.
void main() {
  group('pushOrderCode', () {
    test('reads the camelCase key the backend renderer emits', () {
      expect(
        pushOrderCode(const {'type': 'order', 'orderCode': 'VSORD1007'}),
        'VSORD1007',
      );
    });

    test('reads the snake_case key older payloads carry', () {
      // Reading only one spelling silently disabled the refresh for half the
      // pushes — invisible, because the banner still appeared.
      expect(pushOrderCode(const {'order_code': 'VSORD1007'}), 'VSORD1007');
    });

    test('prefers the camelCase key when both are present', () {
      expect(
        pushOrderCode(const {'orderCode': 'NEW', 'order_code': 'OLD'}),
        'NEW',
      );
    });

    test('a push about no order returns null', () {
      expect(pushOrderCode(const {'type': 'offer', 'route': '/offers'}), isNull);
      expect(pushOrderCode(const {}), isNull);
    });

    test('an empty or whitespace code counts as no order', () {
      // Otherwise the app would invalidate `orderById("")` and fire a doomed
      // request on every promo push.
      expect(pushOrderCode(const {'orderCode': ''}), isNull);
      expect(pushOrderCode(const {'orderCode': '   '}), isNull);
      expect(pushOrderCode(const {'order_code': ''}), isNull);
    });

    test('falls through an empty camelCase key to a populated snake_case one', () {
      expect(
        pushOrderCode(const {'orderCode': '', 'order_code': 'VSORD9'}),
        'VSORD9',
      );
    });

    test('a non-string value is coerced and trimmed', () {
      // FCM data values arrive as strings, but the local-notifications
      // round-trip and test doubles can hand back other types.
      expect(pushOrderCode(const {'orderCode': 12345}), '12345');
      expect(pushOrderCode(const {'orderCode': ' VSORD3 '}), 'VSORD3');
    });
  });
}
