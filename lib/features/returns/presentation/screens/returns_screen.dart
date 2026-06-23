import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../data/returns_data.dart';
import '../providers/returns_providers.dart';

/// Maps a return status string to a chip tone.
VSStatusTone _tone(String status) => switch (status) {
      'refunded' => VSStatusTone.success,
      'rejected' => VSStatusTone.danger,
      'approved' => VSStatusTone.warning,
      'picked' => VSStatusTone.warning,
      _ => VSStatusTone.info,
    };

/// Human label for a return status.
String _label(String status) => switch (status) {
      'requested' => 'Requested',
      'approved' => 'Approved',
      'rejected' => 'Rejected',
      'picked' => 'Picked Up',
      'refunded' => 'Refunded',
      _ => status,
    };

/// Returns & refunds list — one card per request the customer has raised.
class ReturnsScreen extends ConsumerWidget {
  const ReturnsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final returnsAsync = ref.watch(returnsProvider);
    return Scaffold(
      appBar: const VSAppBar(title: 'Returns & Refunds'),
      body: returnsAsync.when(
        loading: () => const VSLoadingView(),
        error: (e, _) => VSErrorView(
          failure: e is Failure ? e : null,
          onRetry: () => ref.invalidate(returnsProvider),
        ),
        data: (returns) {
          if (returns.isEmpty) {
            return const VSEmptyState(
              title: 'No returns yet',
              message:
                  'Returns and refunds you request will appear here.',
              icon: Icons.assignment_return_outlined,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(returnsProvider),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: AppSpacing.screen,
              itemCount: returns.length,
              separatorBuilder: (_, __) => AppSpacing.vGapMd,
              itemBuilder: (_, i) => _ReturnCard(request: returns[i]),
            ),
          );
        },
      ),
    );
  }
}

class _ReturnCard extends StatelessWidget {
  const _ReturnCard({required this.request});

  final ReturnRequest request;

  @override
  Widget build(BuildContext context) {
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
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.id.isEmpty ? request.reason : '#${request.id}',
                      style: AppTypography.titleMedium,
                    ),
                    Text(
                      'Order ${request.orderCode}',
                      style: AppTypography.bodySmall
                          .copyWith(color: vs.textSecondary),
                    ),
                  ],
                ),
              ),
              VSStatusChip(
                label: _label(request.status),
                tone: _tone(request.status),
                dense: true,
              ),
            ],
          ),
          const Divider(height: AppSpacing.xl),
          _InfoRow(
            icon: Icons.label_outline_rounded,
            label: 'Reason',
            value: request.reason,
          ),
          AppSpacing.vGapSm,
          _InfoRow(
            icon: Icons.payments_outlined,
            label: 'Refund',
            value: request.refundAmount.asCurrency,
          ),
          AppSpacing.vGapSm,
          _InfoRow(
            icon: Icons.event_outlined,
            label: 'Requested',
            value: DateFormat('d MMM yyyy').format(request.createdAt),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: vs.textSecondary),
        AppSpacing.hGapSm,
        Text('$label: ',
            style: AppTypography.bodySmall.copyWith(color: vs.textSecondary)),
        Expanded(
          child: Text(value, style: AppTypography.bodyMedium),
        ),
      ],
    );
  }
}
