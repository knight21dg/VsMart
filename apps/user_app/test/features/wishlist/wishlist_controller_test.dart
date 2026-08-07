import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/wishlist/presentation/providers/wishlist_providers.dart';
import 'package:user_app/shared/providers/core_providers.dart';

import '../../helpers/fake_api_client.dart';
import '../../helpers/fake_hive_service.dart';

ProviderContainer _c(FakeHiveService hive) {
  final c = ProviderContainer(overrides: [
    hiveServiceProvider.overrideWithValue(hive),
    apiClientProvider.overrideWithValue(FakeApiClient()),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('WishlistController (offline-optimistic)', () {
    test('toggle adds (most-recent first) then removes', () async {
      final c = _c(FakeHiveService());
      final ctrl = c.read(wishlistProvider.notifier);
      await ctrl.toggle('p1');
      expect(c.read(wishlistProvider), ['p1']);
      expect(ctrl.contains('p1'), true);

      await ctrl.toggle('p2');
      expect(c.read(wishlistProvider), ['p2', 'p1']); // newest first

      await ctrl.toggle('p1'); // toggling again removes
      expect(c.read(wishlistProvider), ['p2']);
      expect(ctrl.contains('p1'), false);
    });

    test('remove and clear', () async {
      final c = _c(FakeHiveService());
      final ctrl = c.read(wishlistProvider.notifier);
      await ctrl.toggle('a');
      await ctrl.toggle('b');
      await ctrl.remove('a');
      expect(c.read(wishlistProvider), ['b']);
      await ctrl.clear();
      expect(c.read(wishlistProvider), isEmpty);
    });

    test('persists to cache across rebuilds (survives offline / restart)', () async {
      final hive = FakeHiveService();
      final c1 = ProviderContainer(overrides: [
        hiveServiceProvider.overrideWithValue(hive),
        apiClientProvider.overrideWithValue(FakeApiClient()),
      ]);
      await c1.read(wishlistProvider.notifier).toggle('saved1');
      c1.dispose();
      // New container, SAME Hive → build() hydrates from cache (API sync fails).
      final c2 = _c(hive);
      expect(c2.read(wishlistProvider), contains('saved1'));
    });
  });
}
