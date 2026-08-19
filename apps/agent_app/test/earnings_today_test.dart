import 'package:flutter_test/flutter_test.dart';
import 'package:agent_app/features/dashboard/data/dashboard_data.dart';

/// The dashboard tile is labelled "Earned today" but rendered `total` — a
/// LIFETIME figure — so a rider who had earned nothing that day still saw a
/// large number, and it never moved when they completed a drop.
void main() {
  group('AgentEarnings — today vs lifetime', () {
    test('today is read from todayTotal, not from the lifetime total', () {
      final e = AgentEarnings.fromMap(const {
        'base': 500.0,
        'incentives': 0.0,
        'total': 500.0,
        'todayBase': 50.0,
        'todayIncentives': 0.0,
        'todayTotal': 50.0,
        'todayDeliveries': 1,
        'todayCollections': 0,
      });

      expect(e.total, 500.0, reason: 'lifetime must stay lifetime');
      expect(e.earnedToday, 50.0, reason: 'the tile must show today only');
      expect(e.hasToday, isTrue);
      expect(e.todayDeliveries, 1);
    });

    test('a day with lifetime money but nothing earned today reads zero', () {
      final e = AgentEarnings.fromMap(const {
        'base': 900.0,
        'incentives': 0.0,
        'total': 900.0,
        'todayTotal': 0.0,
        'todayDeliveries': 0,
      });

      expect(e.total, 900.0);
      expect(e.earnedToday, 0.0);
      expect(e.hasToday, isTrue, reason: 'zero is a real answer, not a missing one');
    });

    test('an older backend that omits the field is reported as unknown', () {
      final e = AgentEarnings.fromMap(const {
        'base': 300.0,
        'incentives': 20.0,
        'total': 320.0,
      });

      expect(e.total, 320.0);
      expect(e.hasToday, isFalse,
          reason: 'the tile shows a dash rather than a confident wrong number');
    });
  });
}
