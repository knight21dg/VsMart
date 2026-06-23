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
import '../../../../shared/providers/core_providers.dart';
import '../../domain/entities/statement.dart';
import '../providers/billing_providers.dart';
import '../widgets/transaction_tile.dart';

/// Statement detail (Phase 4E) — the full per-cycle breakdown: summary,
/// transactions, and a pay action when the statement is open.
class StatementDetailScreen extends ConsumerStatefulWidget {
  const StatementDetailScreen({super.key, required this.statementId});

  final String statementId;

  @override
  ConsumerState<StatementDetailScreen> createState() =>
      _StatementDetailScreenState();
}

class _StatementDetailScreenState
    extends ConsumerState<StatementDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(analyticsServiceProvider)
          .track('statement_opened', {'id': widget.statementId});
    });
  }

  @override
  Widget build(BuildContext context) {
    final statementAsync =
        ref.watch(statementByIdProvider(widget.statementId));
    return Scaffold(
      appBar: VSAppBar(
        title: 'Statement',
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Download',
            onPressed: () => context.showSnack('Statement downloaded'),
          ),
        ],
      ),
      body: statementAsync.when(
        loading: () => const VSLoadingView(),
        error: (e, _) => VSErrorView(
          failure: e is Failure ? e : null,
          onRetry: () =>
              ref.invalidate(statementByIdProvider(widget.statementId)),
        ),
        data: (statement) {
          if (statement == null) {
            return const VSEmptyState(
              title: 'Statement not found',
              icon: Icons.description_outlined,
            );
          }
          return _Body(statement: statement);
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.statement});

  final Statement statement;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: AppSpacing.screen,
            children: [
              _SummaryCard(statement: statement),
              AppSpacing.vGapLg,
              Text('Transactions', style: AppTypography.titleLarge),
              AppSpacing.vGapSm,
              if (statement.transactions.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Text('No transactions in this cycle.',
                      style: AppTypography.bodyMedium
                          .copyWith(color: vs.textSecondary)),
                )
              else
                for (var i = 0; i < statement.transactions.length; i++)
                  TransactionTile(
                    entry: statement.transactions[i],
                    showDivider: i != statement.transactions.length - 1,
                  ),
            ],
          ),
        ),
        if (!statement.paid)
          SafeArea(
            minimum: AppSpacing.screen,
            child: VSButton(
              label: 'Pay ${statement.amountDue.asCurrency}',
              icon: Icons.payments_rounded,
              onPressed: () => context.pushNamed(RouteNames.repayment),
            ),
          ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.statement});

  final Statement statement;

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(DateFormat('MMMM yyyy').format(statement.generatedDate),
                      style: AppTypography.titleLarge),
                  Text(statement.statementId,
                      style: AppTypography.bodySmall
                          .copyWith(color: vs.textSecondary)),
                ],
              ),
              VSStatusChip(
                label: statement.paid
                    ? 'Paid'
                    : statement.isOverdue
                        ? 'Overdue'
                        : 'Due',
                tone: statement.paid
                    ? VSStatusTone.success
                    : statement.isOverdue
                        ? VSStatusTone.danger
                        : VSStatusTone.warning,
                dense: true,
              ),
            ],
          ),
          const Divider(height: AppSpacing.xl),
          _Row(label: 'Total Amount Due', value: statement.amountDue.asCurrency),
          AppSpacing.vGapSm,
          _Row(label: 'Minimum Due', value: statement.minimumDue.asCurrency),
          AppSpacing.vGapSm,
          _Row(
              label: 'Due Date',
              value: DateFormat('d MMMM yyyy').format(statement.dueDate)),
          AppSpacing.vGapSm,
          _Row(
              label: 'Generated',
              value:
                  DateFormat('d MMMM yyyy').format(statement.generatedDate)),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary)),
        Text(value, style: AppTypography.labelLarge),
      ],
    );
  }
}
