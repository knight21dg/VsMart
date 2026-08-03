import 'package:agent_app/core/services/push_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// The agent shell is a 5-tab IndexedStack:
/// Home 0 · Collections 1 · Deliveries 2 · Verify 3 · Profile 4.
/// [pushTabFor] maps an FCM data payload to the tab a tap should open (or null
/// to leave the tab unchanged). It must agree with the backend payloads in
/// delivery/services.py and cashcollections/services.py.
void main() {
  group('pushTabFor — backend agent payloads', () {
    test('delivery assignment (route) → Deliveries tab', () {
      expect(
        pushTabFor({
          'type': 'delivery',
          'kind': 'delivery_assignment',
          'route': 'deliveries',
          'orderCode': 'VS123',
        }),
        2,
      );
    });

    test('collection assignment (route) → Collections tab', () {
      expect(
        pushTabFor({
          'type': 'payment',
          'kind': 'collection_assignment',
          'route': 'collections',
          'collectionId': '9',
        }),
        1,
      );
    });
  });

  group('pushTabFor — fallbacks when route is absent', () {
    test('kind alone routes delivery', () {
      expect(pushTabFor({'kind': 'delivery_assignment'}), 2);
    });

    test('kind alone routes collection', () {
      expect(pushTabFor({'kind': 'collection_assignment'}), 1);
    });

    test('type=payment routes to Collections', () {
      expect(pushTabFor({'type': 'payment'}), 1);
    });

    test('type=credit (dues cleared) routes to Collections', () {
      expect(pushTabFor({'type': 'credit'}), 1);
    });

    test('verification kind → Verify tab', () {
      expect(pushTabFor({'kind': 'verification_task'}), 3);
    });
  });

  group('pushTabFor — unknown / empty leaves the tab as-is', () {
    test('empty payload → null', () {
      expect(pushTabFor(const {}), isNull);
    });

    test('unknown type → null', () {
      expect(pushTabFor({'type': 'offer'}), isNull);
    });

    test('null-ish string values do not throw', () {
      expect(pushTabFor({'type': '', 'kind': '', 'route': ''}), isNull);
    });
  });

  group('pushTabFor — route takes precedence', () {
    test('explicit route wins over a mismatched type', () {
      // A "support"-typed push that explicitly asks for deliveries still routes
      // there.
      expect(pushTabFor({'type': 'support', 'route': 'deliveries'}), 2);
    });
  });
}
