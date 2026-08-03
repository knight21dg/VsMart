// Renders the rebuilt dashboard end-to-end against fixture data.
//
// This exists because the screen is a dense grid of money tiles, a feed and a
// pinned action bar — the exact shape that silently overflows on a small
// handset. `testWidgets` fails on a RenderFlex overflow, so pumping the real
// widget at a small viewport is a genuine layout check, not just a smoke test.
import 'package:agent_app/features/cash/cash_data.dart';
import 'package:agent_app/features/cash/cash_providers.dart';
import 'package:agent_app/features/collections/collections_providers.dart';
import 'package:agent_app/features/collections/data/collections_data.dart';
import 'package:agent_app/features/dashboard/data/dashboard_data.dart';
import 'package:agent_app/features/dashboard/presentation/dashboard_providers.dart';
import 'package:agent_app/features/dashboard/presentation/dashboard_screen.dart';
import 'package:agent_app/features/deliveries/data/deliveries_data.dart';
import 'package:agent_app/features/deliveries/presentation/deliveries_providers.dart';
import 'package:agent_app/features/history/history_data.dart';
import 'package:agent_app/features/history/history_providers.dart';
import 'package:agent_app/features/notifications/presentation/notifications_providers.dart';
import 'package:agent_app/features/verification/presentation/verification_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AgentCollection _collection({required double remaining}) =>
    AgentCollection.fromMap({
      'id': '1',
      'status': 'accepted',
      'amount': remaining,
      'remaining': remaining,
      'customer': {'name': 'Anil', 'phone': '+9199'},
    });

HistoryEntry _entry() => HistoryEntry.fromJson({
      'type': 'collection',
      'id': '9',
      'reference': 'COL9',
      'title': 'Collected',
      'subtitle': 'Anil',
      'customerName': 'Anil',
      'status': 'collected',
      'outcome': 'success',
      'amount': '1890.00',
      'closedAt': '2026-07-21T10:30:00Z',
    });

Widget _harness({
  List<AgentCollection> collections = const [],
  List<HistoryEntry> history = const [],
  num inHand = 0,
  bool checkedIn = true,
  String employmentType = 'gig',
}) {
  return ProviderScope(
    overrides: [
      agentProfileProvider.overrideWith((ref) async => AgentProfile(
            id: '1',
            code: 'AG1',
            name: 'Ravi',
            phone: '+919100000021',
            isAvailable: true,
            assignedPincodes: const ['500001'],
            employmentType: employmentType,
          )),
      agentAttendanceProvider.overrideWith((ref) async => AgentAttendance(
            date: '2026-07-21',
            checkInAt: checkedIn ? '2026-07-21T09:00:00Z' : '',
            checkOutAt: '',
            onDuty: checkedIn,
          )),
      agentEarningsProvider.overrideWith((ref) async =>
          const AgentEarnings(base: 200, incentives: 50, total: 250)),
      assignedCollectionsProvider.overrideWith((ref) async => collections),
      assignedDeliveriesProvider.overrideWith(
          (ref) async => <AgentDelivery>[]),
      verificationTasksProvider.overrideWith((ref) async => []),
      cashSummaryProvider.overrideWith((ref) async => CashSummary(
            inHand: inHand,
            collections: const [],
            deposits: const [],
          )),
      recentHistoryProvider.overrideWith((ref) async => history),
      notificationsProvider.overrideWith((ref) async => []),
    ],
    child: const MaterialApp(home: DashboardScreen()),
  );
}

void main() {
  testWidgets('lays out on a small handset without overflowing',
      (tester) async {
    // 360×640 — the smallest screen we realistically support.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness(
      collections: [_collection(remaining: 5490), _collection(remaining: 1890)],
      history: [_entry()],
      inHand: 2400,
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the money tiles and the action bar', (tester) async {
    await tester.pumpWidget(_harness(
      collections: [_collection(remaining: 5490)],
      history: [_entry()],
      inHand: 2400,
    ));
    await tester.pumpAndSettle();

    // "Yet to Collect" / "Cash in Hand" — the pair must never read as though
    // money still with customers is money the agent is already holding.
    expect(find.text('Yet to Collect'), findsOneWidget);
    expect(find.text('Cash in Hand'), findsOneWidget);
    expect(find.text('Collect Cash'), findsOneWidget);
    expect(find.text('Pending tasks (1)'), findsOneWidget);
    // A gig agent is paid per task, so today's earnings are shown.
    expect(find.text('Earned today'), findsOneWidget);
  });

  testWidgets('a monthly employee sees no earnings tile, but keeps their tasks',
      (tester) async {
    await tester.pumpWidget(_harness(
      collections: [_collection(remaining: 5490)],
      employmentType: 'monthly',
    ));
    await tester.pumpAndSettle();

    expect(find.text('Earned today'), findsNothing);
    // Everything else on the tile grid — including the task list — is
    // unaffected; a monthly employee's default view is still their tasks.
    expect(find.text('Deliveries pending'), findsOneWidget);
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Pending tasks (1)'), findsOneWidget);
  });

  testWidgets('Yet to Collect sums the outstanding across collections',
      (tester) async {
    await tester.pumpWidget(_harness(
      collections: [
        _collection(remaining: 5490),
        _collection(remaining: 1890),
      ],
    ));
    await tester.pumpAndSettle();

    // 5490 + 1890 = 7380 — the agent's total exposure, not a single task's.
    expect(find.text('₹7,380.00'), findsOneWidget);
  });

  testWidgets('empty state reads as empty, not as a failure', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.text('₹0.00'), findsWidgets);
    expect(find.text('All clear — nothing pending right now.'), findsOneWidget);
    expect(find.text('Nothing pending'), findsOneWidget);
  });

  // Split across two tests rather than re-pumping: a second pumpWidget reuses
  // the existing ProviderScope element, so the already-resolved override would
  // still be in place and the assertion would test nothing.
  testWidgets('check-in banner shows before the shift starts', (tester) async {
    await tester.pumpWidget(_harness(checkedIn: false));
    await tester.pumpAndSettle();
    expect(find.text('Check in to start your shift'), findsOneWidget);
  });

  testWidgets('check-in banner is gone once checked in', (tester) async {
    await tester.pumpWidget(_harness(checkedIn: true));
    await tester.pumpAndSettle();
    expect(find.text('Check in to start your shift'), findsNothing);
  });
}
