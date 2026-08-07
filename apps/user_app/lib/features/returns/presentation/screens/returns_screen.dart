import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/generated/app_localizations.dart';
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
String _label(AppLocalizations l10n, String status) => switch (status) {
      'requested' => l10n.returnStatusRequested,
      'approved' => l10n.returnStatusApproved,
      'rejected' => l10n.returnStatusRejected,
      'picked' => l10n.returnStatusPicked,
      'refunded' => l10n.returnStatusRefunded,
      _ => status,
    };

/// Returns & refunds list — one card per request the customer has raised.
class ReturnsScreen extends ConsumerWidget {
  const ReturnsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final returnsAsync = ref.watch(returnsProvider);
    return Scaffold(
      appBar: VSAppBar(title: context.l10n.returnsTitle),
      body: returnsAsync.when(
        loading: () => const VSLoadingView(),
        error: (e, _) => VSErrorView(
          failure: e is Failure ? e : null,
          onRetry: () => ref.invalidate(returnsProvider),
        ),
        data: (returns) {
          if (returns.isEmpty) {
            return VSEmptyState(
              title: context.l10n.returnsEmptyTitle,
              message: context.l10n.returnsEmptyBody,
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
    final l10n = context.l10n;
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
                      l10n.returnsOrderNumber(request.orderCode),
                      style: AppTypography.bodySmall
                          .copyWith(color: vs.textSecondary),
                    ),
                  ],
                ),
              ),
              VSStatusChip(
                label: _label(l10n, request.status),
                tone: _tone(request.status),
                dense: true,
              ),
            ],
          ),
          const Divider(height: AppSpacing.xl),
          _InfoRow(
            icon: Icons.label_outline_rounded,
            label: l10n.returnsReasonLabel,
            value: request.reason,
          ),
          AppSpacing.vGapSm,
          _InfoRow(
            icon: Icons.payments_outlined,
            label: l10n.returnsRefundLabel,
            value: request.refundAmount.asCurrency,
          ),
          AppSpacing.vGapSm,
          _InfoRow(
            icon: Icons.event_outlined,
            label: l10n.returnStatusRequested,
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
