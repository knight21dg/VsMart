import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/statement.dart';
import '../providers/billing_providers.dart';

/// Statements list (Phase 4E) — one card per billing cycle. Tapping opens the
/// per-cycle statement detail.
class StatementsScreen extends ConsumerWidget {
  const StatementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statementsAsync = ref.watch(statementsProvider);
    return Scaffold(
      appBar: const VSAppBar(title: 'Statements'),
      body: statementsAsync.when(
        loading: () => const VSLoadingView(),
        error: (e, _) => VSErrorView(
          failure: e is Failure ? e : null,
          onRetry: () => ref.invalidate(statementsProvider),
        ),
        data: (statements) {
          if (statements.isEmpty) {
            return const VSEmptyState(
              title: 'No statements yet',
              message: 'Your billing statements will appear here.',
              icon: Icons.description_outlined,
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(statementsProvider),
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: AppSpacing.screen,
              itemCount: statements.length,
              separatorBuilder: (_, __) => AppSpacing.vGapMd,
              itemBuilder: (_, i) => _StatementCard(statement: statements[i]),
            ),
          );
        },
      ),
    );
  }
}

class _StatementCard extends StatelessWidget {
  const _StatementCard({required this.statement});

  final Statement statement;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final period = DateFormat('MMMM yyyy').format(statement.generatedDate);
    final (tone, label) = statement.paid
        ? (VSStatusTone.success, 'Paid')
        : statement.isOverdue
            ? (VSStatusTone.danger, 'Overdue')
            : (VSStatusTone.warning, 'Due');
    return InkWell(
      onTap: () => context.pushNamed(
        RouteNames.statementDetail,
        pathParameters: {'id': statement.statementId},
      ),
      borderRadius: AppRadius.brLg,
      child: Container(
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(period, style: AppTypography.titleMedium),
                      Text(statement.statementId,
                          style: AppTypography.bodySmall
                              .copyWith(color: vs.textSecondary)),
                    ],
                  ),
                ),
                VSStatusChip(label: label, tone: tone, dense: true),
              ],
            ),
            const Divider(height: AppSpacing.xl),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _Metric(
                    label: 'Amount Due',
                    value: statement.amountDue.asCurrency,
                    color: statement.paid ? vs.success : vs.danger),
                _Metric(
                    label: 'Due Date',
                    value: DateFormat('d MMM').format(statement.dueDate)),
                Icon(Icons.chevron_right_rounded, color: vs.textSecondary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppTypography.bodySmall.copyWith(color: vs.textSecondary)),
        Text(value, style: AppTypography.labelLarge.copyWith(color: color)),
      ],
    );
  }
}
