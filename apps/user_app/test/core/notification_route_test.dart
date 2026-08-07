import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/core/services/notification_route.dart';

/// The in-app list and the push handler both route off this helper. They used
/// to disagree — push treated `route` as a path, the list as a route name — so
/// every parameterized notification threw when tapped inside the app.
void main() {
  group('resolveNotificationPath', () {
    test('passes an absolute path through', () {
      expect(resolveNotificationPath('/orders/VS12345'), '/orders/VS12345');
    });

    test('prefixes a bare name so legacy payloads still work', () {
      expect(resolveNotificationPath('offers'), '/offers');
      expect(resolveNotificationPath('credit'), '/credit');
    });

    test('trims surrounding whitespace', () {
      expect(resolveNotificationPath('  /orders  '), '/orders');
    });

    test('returns null for anything unusable', () {
      expect(resolveNotificationPath(null), isNull);
      expect(resolveNotificationPath(''), isNull);
      expect(resolveNotificationPath('   '), isNull);
      expect(resolveNotificationPath(42), isNull);
    });

    test('refuses an absolute URL', () {
      // A notification must not be able to send the app off to an arbitrary
      // destination.
      expect(resolveNotificationPath('https://evil.example/x'), isNull);
      expect(resolveNotificationPath('javascript://alert(1)'), isNull);
    });
  });
}
