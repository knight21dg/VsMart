import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/app/theme/app_theme.dart';
import 'package:user_app/l10n/generated/app_localizations.dart';

/// Pumps [screen] inside the app's REAL theme + localization, backed by
/// [container] so a test can read provider state after interactions.
///
/// No GoRouter is wired — keep widget tests to rendering + in-screen state
/// changes, not navigation (navigation is covered by controller/integration tests).
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  required ProviderContainer container,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: screen,
      ),
    ),
  );
  await tester.pump(); // let async providers (bill/estimate) settle one frame
}
