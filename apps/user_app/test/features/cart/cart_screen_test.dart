import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/core/widgets/vs_offline_banner.dart';
import 'package:user_app/features/cart/presentation/providers/cart_providers.dart';
import 'package:user_app/features/cart/presentation/screens/cart_screen.dart';
import 'package:user_app/features/cart/presentation/widgets/cart_widgets.dart';
import 'package:user_app/shared/providers/core_providers.dart';

import '../../helpers/fake_cart_repository.dart';
import '../../helpers/fake_checkout_deps.dart';
import '../../helpers/widget_harness.dart';

ProviderContainer _container({bool empty = true}) {
  final c = ProviderContainer(overrides: [
    cartRepositoryProvider.overrideWithValue(FakeCartRepository(empty ? [] : null)),
    cartBillProvider.overrideWith((ref) async => null),
    cartValidationServiceProvider.overrideWithValue(FakeCartValidationService()),
    commerceConnectivityProvider.overrideWithValue(CommerceConnectivity.online),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('CartScreen', () {
    testWidgets('empty cart renders the empty-cart state', (tester) async {
      await pumpScreen(tester, const CartScreen(), container: _container());
      expect(find.byType(VSEmptyCart), findsOneWidget);
    });
  });

  group('VSOfflineBanner', () {
    ProviderContainer plain() {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      return c;
    }

    testWidgets('shows the offline message when offline', (tester) async {
      await pumpScreen(tester, const Scaffold(body: VSOfflineBanner(offline: true)),
          container: plain());
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    });

    testWidgets('is invisible when online', (tester) async {
      await pumpScreen(tester, const Scaffold(body: VSOfflineBanner()),
          container: plain());
      expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
    });
  });
}
