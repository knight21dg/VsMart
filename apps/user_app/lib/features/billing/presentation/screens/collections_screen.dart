import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/l10n/status_labels.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/billing_enums.dart';
import '../../domain/entities/collection_record.dart';
import '../providers/billing_providers.dart';

/// Maps a [CollectionStatus] to a chip tone.
VSStatusTone _tone(CollectionStatus status) => switch (status) {
      CollectionStatus.collected => VSStatusTone.success,
      CollectionStatus.assigned => VSStatusTone.info,
      CollectionStatus.pending => VSStatusTone.warning,
      CollectionStatus.failed => VSStatusTone.danger,
    };

/// Collections (Phase 4I) — the customer's cash-collection requests. The shape
/// is shared with the Agent App, which assigns an agent and flips the status.
class CollectionsScreen extends ConsumerWidget {
  const CollectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collectionsAsync = ref.watch(collectionsProvider);
    return Scaffold(
      appBar: VSAppBar(title: context.l10n.billingCollections),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.pushNamed(RouteNames.cashCollectionRequest),
        backgroundColor: AppColors.vsGreen,
        foregroundColor: AppColors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text(context.l10n.billingRequest),
      ),
      body: collectionsAsync.when(
        loading: () => const VSLoadingView(),
        error: (e, _) => VSErrorView(
          failure: e is Failure ? e : null,
          onRetry: () => ref.invalidate(collectionsProvider),
        ),
        data: (records) {
          if (records.isEmpty) {
            return VSEmptyState(
              title: context.l10n.billingNoCollections,
              message: context.l10n.billingCollectionsAppearHere,
              icon: Icons.local_atm_outlined,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(collectionsProvider),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: AppSpacing.screen,
              itemCount: records.length,
              separatorBuilder: (_, __) => AppSpacing.vGapMd,
              itemBuilder: (_, i) => _CollectionCard(record: records[i]),
            ),
          );
        },
      ),
    );
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({required this.record});

  final CollectionRecord record;

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
              Container(
                height: 44,
                width: 44,
                decoration:
                    BoxDecoration(color: vs.offerTint, shape: BoxShape.circle),
                child: Icon(Icons.local_atm_rounded, color: vs.offer, size: 22),
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(record.amount.asCurrency,
                        style: AppTypography.titleMedium),
                    Text(
                      context.l10n.billingRequestedOn(
                          DateFormat('d MMM yyyy').format(record.createdAt)),
                      style: AppTypography.bodySmall
                          .copyWith(color: vs.textSecondary),
                    ),
                  ],
                ),
              ),
              VSStatusChip(
                label: record.status.labelL10n(context.l10n),
                tone: _tone(record.status),
                dense: true,
              ),
            ],
          ),
          if (record.isAssigned || record.address != null) ...[
            const Divider(height: AppSpacing.xl),
            if (record.isAssigned)
              _InfoRow(
                icon: Icons.person_outline_rounded,
                label: context.l10n.billingAgent,
                value: record.agentName ?? record.agentId ?? '—',
              ),
            if (record.collectedAt != null) ...[
              AppSpacing.vGapSm,
              _InfoRow(
                icon: Icons.event_available_rounded,
                label: context.l10n.billingCollected,
                value: DateFormat('d MMM yyyy').format(record.collectedAt!),
              ),
            ],
            if (record.address != null) ...[
              AppSpacing.vGapSm,
              _InfoRow(
                icon: Icons.location_on_outlined,
                label: context.l10n.billingAddress,
                value: record.address!,
              ),
            ],
          ],
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
