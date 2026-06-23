import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../data/subscription_data.dart';
import '../providers/subscription_providers.dart';

/// Maps a subscription [status] to a chip tone.
VSStatusTone _tone(String status) => switch (status) {
      'active' => VSStatusTone.success,
      'paused' => VSStatusTone.offer,
      'cancelled' => VSStatusTone.neutral,
      _ => VSStatusTone.neutral,
    };

/// Human label for a subscription [status].
String _statusLabel(String status) => switch (status) {
      'active' => 'Active',
      'paused' => 'Paused',
      'cancelled' => 'Cancelled',
      _ => status,
    };

/// Human label for a delivery [frequency].
String _frequencyLabel(String frequency) => switch (frequency) {
      'weekly' => 'week',
      'biweekly' => '2 weeks',
      'monthly' => 'month',
      _ => frequency,
    };

/// Formats an ISO date string for display, falling back to the raw value.
String _formatDate(String? raw) {
  if (raw == null || raw.isEmpty) return '—';
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  return DateFormat('d MMM yyyy').format(parsed);
}

/// Subscriptions — the customer's recurring product deliveries. Each can be
/// paused, resumed or cancelled; changes flow back to `/subscriptions/{id}`.
class SubscriptionsScreen extends ConsumerWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscriptionsAsync = ref.watch(subscriptionsProvider);
    return Scaffold(
      appBar: const VSAppBar(title: 'Subscriptions'),
      body: subscriptionsAsync.when(
        loading: () => const VSLoadingView(),
        error: (e, _) => VSErrorView(
          failure: e is Failure ? e : null,
          onRetry: () => ref.invalidate(subscriptionsProvider),
        ),
        data: (subscriptions) {
          if (subscriptions.isEmpty) {
            return const VSEmptyState(
              title: 'No subscriptions yet',
              message:
                  'Set up a recurring delivery and your subscriptions will '
                  'appear here.',
              icon: Icons.shopping_basket_outlined,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(subscriptionsProvider),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: AppSpacing.screen,
              itemCount: subscriptions.length,
              separatorBuilder: (_, __) => AppSpacing.vGapMd,
              itemBuilder: (_, i) =>
                  _SubscriptionCard(subscription: subscriptions[i]),
            ),
          );
        },
      ),
    );
  }
}

class _SubscriptionCard extends ConsumerWidget {
  const _SubscriptionCard({required this.subscription});

  final Subscription subscription;

  Future<void> _runAction(
    BuildContext context,
    WidgetRef ref,
    String action,
    String successMessage,
  ) async {
    final dataSource = ref.read(subscriptionDataSourceProvider);
    try {
      if (action == 'cancel') {
        await dataSource.cancel(subscription.id);
      } else {
        await dataSource.updateAction(subscription.id, action);
      }
      if (!context.mounted) return;
      ref.invalidate(subscriptionsProvider);
      context.showSnack(successMessage);
    } catch (_) {
      if (!context.mounted) return;
      context.showSnack('Could not update subscription', isError: true);
    }
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel subscription?'),
        content: Text(
          'You will stop receiving ${subscription.productName}. This cannot '
          'be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: context.vsColors.danger),
            child: const Text('Cancel subscription'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _runAction(context, ref, 'cancel', 'Subscription cancelled');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              VSNetworkImage(
                url: subscription.imageUrl,
                width: 56,
                height: 56,
                borderRadius: AppRadius.brMd,
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subscription.productName,
                      style: AppTypography.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    AppSpacing.vGapXs,
                    Text(
                      subscription.price.asCurrency,
                      style: AppTypography.bodyMedium
                          .copyWith(color: vs.textSecondary),
                    ),
                  ],
                ),
              ),
              AppSpacing.hGapSm,
              _ActionsMenu(
                subscription: subscription,
                onPause: () => _runAction(
                  context,
                  ref,
                  'pause',
                  'Subscription paused',
                ),
                onResume: () => _runAction(
                  context,
                  ref,
                  'resume',
                  'Subscription resumed',
                ),
                onCancel: () => _confirmCancel(context, ref),
              ),
            ],
          ),
          const Divider(height: AppSpacing.xl),
          Row(
            children: [
              VSStatusChip(
                label: _statusLabel(subscription.status),
                tone: _tone(subscription.status),
                dense: true,
              ),
              AppSpacing.hGapSm,
              Icon(Icons.repeat_rounded, size: 16, color: vs.textSecondary),
              const SizedBox(width: 4),
              Text(
                'Every ${_frequencyLabel(subscription.frequency)}',
                style: AppTypography.bodySmall.copyWith(color: vs.textSecondary),
              ),
            ],
          ),
          AppSpacing.vGapSm,
          Row(
            children: [
              Icon(Icons.event_outlined, size: 16, color: vs.textSecondary),
              AppSpacing.hGapSm,
              Text(
                'Next delivery: ',
                style:
                    AppTypography.bodySmall.copyWith(color: vs.textSecondary),
              ),
              Text(
                _formatDate(subscription.nextDelivery),
                style: AppTypography.bodyMedium,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Overflow menu offering Pause/Resume (by status) and Cancel.
class _ActionsMenu extends StatelessWidget {
  const _ActionsMenu({
    required this.subscription,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
  });

  final Subscription subscription;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    if (subscription.isCancelled) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, color: vs.textSecondary),
      onSelected: (value) {
        switch (value) {
          case 'pause':
            onPause();
          case 'resume':
            onResume();
          case 'cancel':
            onCancel();
        }
      },
      itemBuilder: (_) => [
        if (subscription.isActive)
          const PopupMenuItem<String>(
            value: 'pause',
            child: Row(
              children: [
                Icon(Icons.pause_circle_outline_rounded, size: 20),
                SizedBox(width: AppSpacing.md),
                Text('Pause'),
              ],
            ),
          ),
        if (subscription.isPaused)
          const PopupMenuItem<String>(
            value: 'resume',
            child: Row(
              children: [
                Icon(Icons.play_circle_outline_rounded, size: 20),
                SizedBox(width: AppSpacing.md),
                Text('Resume'),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'cancel',
          child: Row(
            children: [
              Icon(Icons.cancel_outlined, size: 20, color: vs.danger),
              const SizedBox(width: AppSpacing.md),
              Text('Cancel', style: TextStyle(color: vs.danger)),
            ],
          ),
        ),
      ],
    );
  }
}
