import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/home/presentation/screens/home_screen.dart';

/// The "Deliver to" header must name the place the order is actually going.
///
/// Regression: live GPS used to win over the chosen delivery address, so a
/// customer standing in Surampalem while delivering to Velangi saw
/// "Deliver to Surampalem" — the header contradicted the address on the order.
void main() {
  group('resolveDeliveryLabel', () {
    test('the chosen address wins over live location', () {
      expect(
        resolveDeliveryLabel(addressLabel: 'Velangi', liveArea: 'Surampalem'),
        'Velangi',
      );
    });

    test('live location is used only when no address is chosen', () {
      expect(
        resolveDeliveryLabel(addressLabel: '', liveArea: 'Surampalem'),
        'Surampalem',
      );
    });

    test('falls back to a prompt when neither is known', () {
      expect(
        resolveDeliveryLabel(addressLabel: '', liveArea: ''),
        'Set delivery address',
      );
    });

    test('an address with no live fix still shows', () {
      expect(
        resolveDeliveryLabel(addressLabel: 'Velangi', liveArea: ''),
        'Velangi',
      );
    });
  });
}
