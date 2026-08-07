// A cash-recovery step that never reached the server must never be reported as
// though it did.
//
// The screen's `_run` used to return `CollectionApiException?`, which is null
// for a SUCCESS and also null for every non-API failure (dropped connection,
// timeout, 5xx). Callers gated their success toast on `err == null`, so with no
// signal the agent was told "OTP sent to the customer to confirm ₹X" for a
// request that never left the phone — and then waited for a code the customer
// was never sent.
import 'package:agent_app/core/api.dart';
import 'package:agent_app/core/token_store.dart';
import 'package:agent_app/features/collections/collections_providers.dart';
import 'package:agent_app/features/collections/data/collections_data.dart';
import 'package:agent_app/features/collections/presentation/collection_detail_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Every call fails the way a phone with no bars fails.
class _OfflineCollectionsRepo extends CollectionsRepo {
  _OfflineCollectionsRepo() : super(Api(TokenStore(_NoopStorage())));

  static DioException _offline(String path) => DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.connectionError,
      );

  @override
  Future<AgentCollection> requestOtp(String id, double amount) async =>
      throw _offline('/collections/$id/request-otp');

  @override
  Future<AgentCollection> verifyOtp(String id, String otp) async =>
      throw _offline('/collections/$id/verify-otp');
}

/// flutter_secure_storage has no platform implementation under `flutter test`;
/// the repo above never reads a token, this just keeps construction inert.
class _NoopStorage implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<String?>.value(null);
}

AgentCollection _reachedTask() => AgentCollection.fromMap({
      'id': '77',
      'status': 'reached',
      'amount': 2000,
      'remaining': 2000,
      'otpVerified': false,
      'otpPending': false,
      'customer': {'name': 'Anil', 'phone': '+919100000021'},
    });

Widget _harness() => ProviderScope(
      overrides: [
        collectionsRepoProvider.overrideWithValue(_OfflineCollectionsRepo()),
        collectionDetailProvider('77').overrideWith((ref) async => _reachedTask()),
      ],
      child: const MaterialApp(home: CollectionDetailScreen(id: '77')),
    );

void main() {
  testWidgets('a failed OTP request is never reported as sent', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    // The action area sits below the fold in a lazy ListView.
    await tester.scrollUntilVisible(
      find.text('Send OTP to customer'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Send OTP to customer'));
    await tester.pump(); // start the call
    await tester.pump(const Duration(milliseconds: 300)); // let it fail

    // The lie that used to appear.
    expect(find.textContaining('OTP sent'), findsNothing);
    // What the agent should see instead: it's the network, so move and retry.
    expect(find.textContaining('offline'), findsOneWidget);
  });
}
