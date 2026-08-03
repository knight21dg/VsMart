import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/ui.dart';
import '../data/collections_data.dart';

/// Digital receipt shown after cash is collected — the agent can show or share
/// this as proof of collection. Reached from the collection detail on a
/// completed (non-partial) collect.
class CollectionReceiptScreen extends StatelessWidget {
  const CollectionReceiptScreen({
    super.key,
    required this.collection,
    required this.collectedAmount,
  });

  final AgentCollection collection;
  final double collectedAmount;

  String get _reference => 'CR-${collection.id}';

  String _dateTime() {
    final dt = DateTime.tryParse(collection.collectedAt)?.toLocal() ??
        DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    return '${dt.day} ${_month(dt.month)} ${dt.year}, '
        '$h:${two(dt.minute)} ${dt.hour < 12 ? 'AM' : 'PM'}';
  }

  static String _month(int m) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m - 1];

  void _share(BuildContext context) {
    final text = 'VS Mart — Payment Receipt\n'
        'Ref: $_reference\n'
        'Customer: ${collection.customerName}\n'
        '${collection.customerPhone.isNotEmpty ? 'Phone: ${collection.customerPhone}\n' : ''}'
        'Total amount: ${agentMoney(collection.amount)}\n'
        'Total collected: ${agentMoney(collection.collectedAmount)}\n'
        'Remaining: ${agentMoney(collection.amountDue)}\n'
        'Method: Cash\n'
        'Date: ${_dateTime()}';
    Clipboard.setData(ClipboardData(text: text));
    showToast(context, 'Receipt copied');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgentColors.bg,
      appBar: AppBar(title: const Text('Receipt')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // success header
          Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                    color: AgentColors.brand.withValues(alpha: 0.12),
                    shape: BoxShape.circle),
                child: const Icon(Icons.check_circle_rounded,
                    color: AgentColors.brand, size: 44),
              ),
              const SizedBox(height: 12),
              const Text('Payment Collected',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AgentColors.textPrimary)),
              const SizedBox(height: 4),
              Text(agentMoney(collectedAmount),
                  style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: AgentColors.brand)),
            ],
          ),
          const SizedBox(height: 20),
          // Payment breakdown — authoritative figures from the settled record.
          const SectionHeader('Payment breakdown'),
          AppCard(
            child: Column(
              children: [
                _Row(label: 'Total amount', value: agentMoney(collection.amount)),
                _Row(
                    label: 'Total collected',
                    value: agentMoney(collection.collectedAmount),
                    valueColor: AgentColors.brand),
                const _Line(),
                _Row(
                    label: 'Remaining balance',
                    value: agentMoney(collection.amountDue),
                    valueColor: collection.amountDue > 0
                        ? AgentColors.amber
                        : AgentColors.brand),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionHeader('Details'),
          AppCard(
            child: Column(
              children: [
                _Row(label: 'Customer', value: collection.customerName),
                if (collection.customerPhone.isNotEmpty)
                  _Row(label: 'Phone', value: collection.customerPhone),
                _Row(label: 'Reference', value: _reference),
                _Row(label: 'Method', value: 'Cash'),
                _Row(label: 'Date & time', value: _dateTime()),
                const _Line(),
                _Row(
                    label: 'Status',
                    value: collection.amountDue > 0
                        ? 'Partially collected'
                        : 'Fully collected',
                    valueColor: AgentColors.brand),
              ],
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => _share(context),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                foregroundColor: AgentColors.brand,
                side: const BorderSide(color: AgentColors.brand)),
            icon: const Icon(Icons.share_rounded),
            label: const Text('Share receipt'),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: AgentColors.textSecondary)),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? AgentColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 4),
        child: Divider(height: 1, color: AgentColors.divider),
      );
}
