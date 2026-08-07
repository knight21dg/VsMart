// The gate between "signed in" and the shell must never strand an agent.
//
// It used to decide on `agentProfileProvider.valueOrNull == null` and show a
// bare spinner — which is exactly what an ERROR looks like through that getter.
// So a dead network, a 5xx or an expired session parked the app on an empty
// screen forever: no message, no retry, no way to sign out. Starting a shift
// out of coverage made the app look bricked.
import 'package:agent_app/app.dart';
import 'package:agent_app/core/providers.dart';
import 'package:agent_app/core/ui.dart';
import 'package:agent_app/features/dashboard/data/dashboard_data.dart';
import 'package:agent_app/features/dashboard/presentation/dashboard_providers.dart';
import 'package:agent_app/features/onboarding/presentation/face_capture_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Authenticated, so the gate gets past the login screen and onto the profile
/// decision — the part under test.
class _AuthedController extends AuthController {
  @override
  AuthStatus build() => AuthStatus.authenticated;
}

Widget _harness(Override profileOverride) => ProviderScope(
      overrides: [
        authStatusProvider.overrideWith(_AuthedController.new),
        profileOverride,
      ],
      child: const AgentApp(),
    );

AgentProfile _profile({String avatarUrl = 'https://cdn/agent.jpg'}) => AgentProfile(
      id: '1',
      code: 'AG1',
      name: 'Ravi',
      phone: '+919100000021',
      isAvailable: true,
      assignedPincodes: const ['500001'],
      employmentType: 'gig',
      avatarUrl: avatarUrl,
    );

void main() {
  testWidgets('profile failure offers a retry instead of an endless spinner',
      (tester) async {
    await tester.pumpWidget(_harness(
      agentProfileProvider.overrideWith((ref) async => throw DioException(
            requestOptions: RequestOptions(path: '/agents/me'),
            type: DioExceptionType.connectionError,
          )),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(ErrorRetry), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    // And an escape hatch, so a session that can never load isn't a dead end.
    expect(find.text('Sign out'), findsOneWidget);
    // The agent is told it's the network, not something they did wrong.
    expect(find.textContaining('offline'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('retry re-runs the profile call and lets the agent through',
      (tester) async {
    var attempt = 0;
    await tester.pumpWidget(_harness(
      agentProfileProvider.overrideWith((ref) async {
        attempt++;
        if (attempt == 1) {
          throw DioException(
            requestOptions: RequestOptions(path: '/agents/me'),
            type: DioExceptionType.connectionError,
          );
        }
        // Second attempt succeeds. Deliberately a profile with no photo, so the
        // gate advances to face capture rather than the shell — the shell would
        // mount the real dashboard repos and reach for the network.
        return _profile(avatarUrl: '');
      }),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorRetry), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(attempt, 2);
    expect(find.byType(ErrorRetry), findsNothing);
    expect(find.byType(FaceCaptureScreen), findsOneWidget);
  });

  testWidgets('an agent with no photo still lands on face capture',
      (tester) async {
    await tester.pumpWidget(_harness(
      agentProfileProvider.overrideWith((ref) async => _profile(avatarUrl: '')),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(FaceCaptureScreen), findsOneWidget);
    expect(find.byType(ErrorRetry), findsNothing);
  });
}
