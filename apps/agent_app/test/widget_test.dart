// Smoke test: the agent app boots to its auth gate without throwing.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agent_app/app.dart';

void main() {
  testWidgets('AgentApp boots without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: AgentApp()));
    // The auth gate shows a loading spinner until token state resolves.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
