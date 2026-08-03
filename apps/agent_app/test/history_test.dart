import 'package:agent_app/features/history/history_data.dart';
import 'package:agent_app/features/history/history_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HistoryEntry.fromJson', () {
    test('parses a completed delivery', () {
      final e = HistoryEntry.fromJson({
        'type': 'delivery',
        'id': '7',
        'reference': 'ORD-1',
        'title': 'Order ORD-1',
        'subtitle': '12 MG Road',
        'status': 'delivered',
        'outcome': 'success',
        'amount': '250.00',
        'closedAt': '2026-07-21T10:30:00Z',
      });
      expect(e.kind, HistoryKind.delivery);
      expect(e.outcome, HistoryOutcome.success);
      expect(e.amount, 250.00);
      expect(e.closedAt, isNotNull);
    });

    test('parses a partial collection with both figures', () {
      final e = HistoryEntry.fromJson({
        'type': 'collection',
        'id': '3',
        'status': 'partially_collected',
        'outcome': 'partial',
        'amount': '200.00',
        'amountDue': '500.00',
      });
      expect(e.kind, HistoryKind.collection);
      expect(e.outcome, HistoryOutcome.partial);
      expect(e.amount, 200.00);
      expect(e.amountDue, 500.00);
    });

    test('accepts snake_case keys', () {
      final e = HistoryEntry.fromJson({
        'type': 'verification',
        'id': '9',
        'outcome': 'failed',
        'customer_name': 'Anil',
        'failure_reason': 'address_not_found',
        'closed_at': '2026-07-20T08:00:00Z',
      });
      expect(e.customerName, 'Anil');
      expect(e.failureReason, 'address_not_found');
      expect(e.closedAt, isNotNull);
    });

    test('an unknown outcome degrades to failed rather than throwing', () {
      final e = HistoryEntry.fromJson({'type': 'delivery', 'outcome': 'weird'});
      expect(e.outcome, HistoryOutcome.failed);
    });

    test('a null amount stays null instead of becoming zero', () {
      // Verifications carry no money; showing "₹0.00" would read as a real
      // figure rather than "not applicable".
      final e = HistoryEntry.fromJson({'type': 'verification', 'id': '1'});
      expect(e.amount, isNull);
      expect(e.amountDue, isNull);
    });
  });

  group('HistoryFilter', () {
    test('changing kind preserves the date range', () {
      final from = DateTime(2026, 7, 1);
      final to = DateTime(2026, 7, 21);
      final filter =
          const HistoryFilter().withRange(from, to).withKind(HistoryKind.collection);
      expect(filter.kind, HistoryKind.collection);
      expect(filter.from, from);
      expect(filter.to, to);
      expect(filter.hasRange, isTrue);
    });

    test('clearing the range keeps the kind', () {
      final filter = const HistoryFilter()
          .withKind(HistoryKind.delivery)
          .withRange(DateTime(2026, 7, 1), DateTime(2026, 7, 2))
          .withRange(null, null);
      expect(filter.kind, HistoryKind.delivery);
      expect(filter.hasRange, isFalse);
    });

    test('equal filters compare equal so the provider does not reload', () {
      expect(const HistoryFilter().withKind(HistoryKind.delivery),
          const HistoryFilter().withKind(HistoryKind.delivery));
    });
  });

  group('HistoryState', () {
    test('is not empty while still loading', () {
      expect(const HistoryState().isEmpty, isFalse);
    });

    test('is empty once loaded with no rows', () {
      expect(const HistoryState(loading: false).isEmpty, isTrue);
    });

    test('is not empty when an error is showing', () {
      // An error must render the retry view, not the "nothing here yet" view.
      const state = HistoryState(loading: false, error: 'boom');
      expect(state.isEmpty, isFalse);
    });
  });
}
