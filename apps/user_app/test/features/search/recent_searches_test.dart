import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/features/search/presentation/providers/search_providers.dart';
import 'package:user_app/shared/providers/core_providers.dart';

import '../../helpers/fake_hive_service.dart';

ProviderContainer _c(FakeHiveService hive) {
  final c = ProviderContainer(overrides: [
    hiveServiceProvider.overrideWithValue(hive),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('RecentSearchesController', () {
    test('add prepends most-recent and dedups case-insensitively', () async {
      final c = _c(FakeHiveService());
      final ctrl = c.read(recentSearchesProvider.notifier);
      await ctrl.add('Milk');
      await ctrl.add('atta');
      await ctrl.add('MILK'); // duplicate of Milk (case-insensitive)
      expect(c.read(recentSearchesProvider), ['MILK', 'atta']);
    });

    test('ignores empty / whitespace terms', () async {
      final c = _c(FakeHiveService());
      final ctrl = c.read(recentSearchesProvider.notifier);
      await ctrl.add('   ');
      await ctrl.add('');
      expect(c.read(recentSearchesProvider), isEmpty);
    });

    test('caps history at 8, dropping the oldest', () async {
      final c = _c(FakeHiveService());
      final ctrl = c.read(recentSearchesProvider.notifier);
      for (var i = 1; i <= 10; i++) {
        await ctrl.add('term$i');
      }
      final hist = c.read(recentSearchesProvider);
      expect(hist.length, 8);
      expect(hist.first, 'term10'); // most recent
      expect(hist.contains('term1'), false); // oldest dropped
      expect(hist.contains('term2'), false);
    });

    test('remove and clear', () async {
      final c = _c(FakeHiveService());
      final ctrl = c.read(recentSearchesProvider.notifier);
      await ctrl.add('Milk');
      await ctrl.add('Atta');
      await ctrl.remove('Milk');
      expect(c.read(recentSearchesProvider), ['Atta']);
      await ctrl.clear();
      expect(c.read(recentSearchesProvider), isEmpty);
    });

    test('persists across controller rebuilds (same Hive)', () async {
      final hive = FakeHiveService();
      final c1 = ProviderContainer(
          overrides: [hiveServiceProvider.overrideWithValue(hive)]);
      await c1.read(recentSearchesProvider.notifier).add('Rice');
      c1.dispose();
      // New container, SAME Hive → build() reloads the persisted history.
      final c2 = _c(hive);
      expect(c2.read(recentSearchesProvider), ['Rice']);
    });
  });
}
