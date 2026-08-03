import 'package:agent_app/core/ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('agentMoney — strict INR', () {
    test('always shows two decimals', () {
      expect(agentMoney(1250), '₹1,250.00');
      expect(agentMoney(0), '₹0.00');
      expect(agentMoney(5), '₹5.00');
    });

    test('preserves exact paise (never rounds money away)', () {
      expect(agentMoney(1250.50), '₹1,250.50');
      expect(agentMoney(1250.99), '₹1,250.99');
      expect(agentMoney(0.10), '₹0.10');
      expect(agentMoney(0.05), '₹0.05');
    });

    test('Indian digit grouping (lakh / crore)', () {
      expect(agentMoney(999), '₹999.00');
      expect(agentMoney(1000), '₹1,000.00');
      expect(agentMoney(100000), '₹1,00,000.00');
      expect(agentMoney(1234567.89), '₹12,34,567.89');
    });

    test('negatives', () {
      expect(agentMoney(-500.25), '-₹500.25');
    });
  });
}
