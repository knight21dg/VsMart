import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../providers/subscription_providers.dart';

/// "Subscribe & Save" entry point embedded on the product detail screen. Opens a
/// sheet to pick frequency + quantity and creates a recurring subscription.
class SubscribeButton extends ConsumerWidget {
  const SubscribeButton({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return VSOutlinedButton(
      label: 'Subscribe & Save',
      icon: Icons.autorenew_rounded,
      onPressed: () => _openSheet(context, ref),
    );
  }

  void _openSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SubscribeSheet(productId: productId),
    );
  }
}

class _SubscribeSheet extends ConsumerStatefulWidget {
  const _SubscribeSheet({required this.productId});

  final String productId;

  @override
  ConsumerState<_SubscribeSheet> createState() => _SubscribeSheetState();
}

class _SubscribeSheetState extends ConsumerState<_SubscribeSheet> {
  static const _freqs = [
    ('weekly', 'Weekly'),
    ('biweekly', 'Every 2 weeks'),
    ('monthly', 'Monthly'),
  ];

  String _frequency = 'weekly';
  int _quantity = 1;
  bool _saving = false;

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      await ref.read(subscriptionDataSourceProvider).create(
            productId: widget.productId,
            quantity: _quantity,
            frequency: _frequency,
          );
      ref.invalidate(subscriptionsProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      context.showSnack('Subscription started');
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.showSnack('Could not start subscription', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Subscribe & Save', style: AppTypography.titleLarge),
            AppSpacing.vGapXs,
            Text(
              'Get this item delivered on a schedule. Pause or cancel anytime.',
              style: AppTypography.bodySmall.copyWith(color: vs.textSecondary),
            ),
            AppSpacing.vGapLg,
            Text('Delivery frequency', style: AppTypography.titleMedium),
            AppSpacing.vGapSm,
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final (value, label) in _freqs)
                  ChoiceChip(
                    label: Text(label),
                    selected: _frequency == value,
                    onSelected: (_) => setState(() => _frequency = value),
                  ),
              ],
            ),
            AppSpacing.vGapLg,
            Row(
              children: [
                Text('Quantity', style: AppTypography.titleMedium),
                const Spacer(),
                IconButton(
                  onPressed: _quantity > 1
                      ? () => setState(() => _quantity--)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                ),
                Text('$_quantity', style: AppTypography.titleLarge),
                IconButton(
                  onPressed: () => setState(() => _quantity++),
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
              ],
            ),
            AppSpacing.vGapLg,
            VSButton(
              label: 'Start Subscription',
              isLoading: _saving,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
