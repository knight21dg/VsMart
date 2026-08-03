import 'package:flutter/material.dart';

import '../../../core/ui.dart';
import '../data/deliveries_data.dart';

/// Confirmation shown after a delivery is completed — the closing step of the
/// delivery flow.
class DeliverySuccessScreen extends StatelessWidget {
  const DeliverySuccessScreen({super.key, required this.delivery});
  final AgentDelivery delivery;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgentColors.bg,
      appBar: AppBar(title: const Text('Delivered')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
              const Text('Delivery Successful',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AgentColors.textPrimary)),
              if (delivery.orderCode.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(delivery.orderCode,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AgentColors.textSecondary)),
              ],
            ],
          ),
          const SizedBox(height: 20),
          AppCard(
            child: Column(
              children: [
                if (delivery.customerName.isNotEmpty)
                  _Row(label: 'Customer', value: delivery.customerName),
                _Row(label: 'Order value', value: agentMoney(delivery.amount)),
                if (delivery.itemCount > 0)
                  _Row(label: 'Items', value: '${delivery.itemCount}'),
                _Row(
                    label: 'Payment',
                    value: delivery.paymentMethod.isNotEmpty
                        ? delivery.paymentMethod.toUpperCase()
                        : '—'),
                if (delivery.earnings > 0) ...[
                  const Divider(height: 20, color: AgentColors.divider),
                  _Row(
                      label: 'You earned',
                      value: agentMoney(delivery.earnings),
                      valueColor: AgentColors.brand),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
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
          Text(label, style: const TextStyle(color: AgentColors.textSecondary)),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: valueColor ?? AgentColors.textPrimary)),
        ],
      ),
    );
  }
}
