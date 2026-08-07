import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:user_app/app/routes/route_paths.dart';
import 'package:user_app/core/errors/app_error_presenter.dart';
import 'package:user_app/core/errors/failures.dart';
import 'package:user_app/l10n/generated/app_localizations.dart';

/// An actionable failure must REPLACE the destination, not push it.
///
/// Regression for the "save address → blank page" report: the POST failed with
/// AUTH_REQUIRED (expired session), whose action is `navigate:/login`. The
/// presenter pushed that route; the router's redirect rewrote `/login` to
/// `/home` — a StatefulShellRoute branch — and an imperative push of a shell
/// branch onto the ROOT navigator renders blank. The customer was left on an
/// empty screen with their address unsaved and no error shown.
void main() {
  Future<GoRouter> pumpWith(WidgetTester tester, Failure failure) async {
    late BuildContext formContext;
    final router = GoRouter(
      initialLocation: '/form',
      routes: [
        GoRoute(
          path: '/form',
          builder: (context, _) {
            formContext = context;
            return const Scaffold(body: Text('form'));
          },
        ),
        GoRoute(
          path: RoutePaths.login,
          name: RouteNames.login,
          builder: (_, __) => const Scaffold(body: Text('login')),
        ),
        GoRoute(
          path: RoutePaths.home,
          name: RouteNames.home,
          builder: (_, __) => const Scaffold(body: Text('home')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: router,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('form'), findsOneWidget);

    final ref = ProviderScope.containerOf(formContext);
    presentFailure(
      formContext,
      _RefShim(ref),
      failure,
    );
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('a navigate action replaces the route instead of stacking it',
      (tester) async {
    final router = await pumpWith(
      tester,
      const AuthFailure.actionable(
        'Please sign in to continue.',
        code: 'AUTH_REQUIRED',
        actionType: 'navigate',
        actionTarget: '/login',
      ),
    );

    expect(find.text('login'), findsOneWidget);
    // The form must be GONE, not merely covered: a push would leave it beneath,
    // and it is that stacked shell/entry route that rendered blank on device.
    expect(find.text('form'), findsNothing);
    expect(router.routerDelegate.currentConfiguration.matches.length, 1);
  });

  testWidgets('a plain retryable failure keeps the user on the form',
      (tester) async {
    await pumpWith(
      tester,
      const ValidationFailure(
        'Some of the information entered is not valid.',
        code: 'VALIDATION_ERROR',
        severity: 'warning',
        retryable: true,
      ),
    );
    // No navigation at all — the entered details must survive so they can be
    // corrected rather than retyped.
    expect(find.text('form'), findsOneWidget);
    expect(find.text('login'), findsNothing);
  });
}

/// Minimal WidgetRef over a real container — `presentFailure` only ever `read`s.
class _RefShim implements WidgetRef {
  _RefShim(this._container);

  final ProviderContainer _container;

  @override
  T read<T>(ProviderListenable<T> provider) => _container.read(provider);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Not needed for this test: ${invocation.memberName}');
}
