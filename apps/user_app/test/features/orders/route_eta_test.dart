import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/orders/presentation/providers/live_tracking_provider.dart';

/// The tracking map fetches a real road-following ETA from `/geo/route` (a billed
/// Directions call). Its `onEta` callback had no call site, so the figure was
/// discarded and the customer saw the backend's straight-line haversine estimate
/// at a flat 20 km/h instead. [routeEtaProvider] carries it to the headline.
void main() {
  group('routeEtaProvider', () {
    test('starts null so the headline falls back to the backend estimate', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(routeEtaProvider('VS1')), isNull);
    });

    test('holds the ETA the map reports', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(routeEtaProvider('VS1').notifier).state = '18 min';

      expect(container.read(routeEtaProvider('VS1')), '18 min');
    });

    test('is scoped per order, so one order never shows another\'s ETA', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(routeEtaProvider('VS1').notifier).state = '18 min';

      expect(container.read(routeEtaProvider('VS2')), isNull);
    });

    test('a later fetch replaces the earlier ETA', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(routeEtaProvider('VS1').notifier);
      notifier.state = '18 min';
      notifier.state = '6 min';

      expect(container.read(routeEtaProvider('VS1')), '6 min');
    });
  });
}
