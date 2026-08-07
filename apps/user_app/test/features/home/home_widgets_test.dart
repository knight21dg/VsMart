import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/core/widgets/vs_category_card.dart';
import 'package:user_app/core/widgets/vs_shimmer.dart';
import 'package:user_app/features/home/presentation/widgets/vs_home_shimmer.dart';

import '../../helpers/widget_harness.dart';

ProviderContainer _plain() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('Home — loading skeleton', () {
    testWidgets('VSHomeShimmer renders skeleton boxes', (tester) async {
      await pumpScreen(tester, const Scaffold(body: VSHomeShimmer()),
          container: _plain());
      expect(find.byType(VSShimmerBox), findsWidgets); // home shows while loading
    });
  });

  group('Home — category tile', () {
    testWidgets('VSCategoryCard shows label + icon (no network image)',
        (tester) async {
      await pumpScreen(
        tester,
        const Scaffold(
          body: VSCategoryCard(label: 'Fruits', icon: Icons.eco_rounded)),
        container: _plain(),
      );
      expect(find.text('Fruits'), findsOneWidget);
      expect(find.byIcon(Icons.eco_rounded), findsOneWidget);
    });

    testWidgets('VSCategoryCard fires onTap', (tester) async {
      var tapped = false;
      await pumpScreen(
        tester,
        Scaffold(
          body: VSCategoryCard(
            label: 'Dairy', icon: Icons.egg_rounded, onTap: () => tapped = true)),
        container: _plain(),
      );
      await tester.tap(find.byType(VSCategoryCard));
      expect(tapped, true);
    });
  });
}
