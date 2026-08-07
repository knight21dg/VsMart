import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/app_error_presenter.dart';
import '../../../../core/errors/error_handler.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../data/receipt_service.dart';
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
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(analyticsServiceProvider)
          .track('statement_opened', {'id': widget.statementId});
    });
  }

  Future<void> _downloadStatement() async {
    setState(() => _downloading = true);
    try {
      final bytes = await ref
          .read(receiptServiceProvider)
          .fetchStatement(widget.statementId);
      ref
          .read(analyticsServiceProvider)
          .track('statement_downloaded', {'id': widget.statementId});
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'VS-Mart-Statement-${widget.statementId}',
      );
    } catch (e) {
      if (mounted) {
        presentFailure(context, ref, ErrorHandler.handle(e),
            onRetry: _downloadStatement);
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statementAsync =
        ref.watch(statementByIdProvider(widget.statementId));
    return Scaffold(
      appBar: VSAppBar(
        title: context.l10n.billingStatement,
        actions: [
          IconButton(
            icon: _downloading
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_rounded),
            tooltip: context.l10n.commonDownload,
            // Fetches the real statement PDF (native preview → print/save/share).
            // Was a fake 'downloaded' snackbar that fetched nothing.
            onPressed: _downloading ? null : _downloadStatement,
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
            return VSEmptyState(
              title: context.l10n.billingStatementNotFound,
              icon: Icons.description_outlined,
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              // The by-id family derives from the statements list — refetch it.
              ref.invalidate(statementsProvider);
              await ref.read(statementByIdProvider(widget.statementId).future);
            },
            child: _Body(statement: statement),
          );
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
            physics: const AlwaysScrollableScrollPhysics(),
            padding: AppSpacing.screen,
            children: [
              _SummaryCard(statement: statement),
              AppSpacing.vGapLg,
              Text(context.l10n.billingTransactions,
                  style: AppTypography.titleLarge),
              AppSpacing.vGapSm,
              if (statement.transactions.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Text(context.l10n.billingNoTransactionsInCycle,
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
              label: context.l10n.billingPayAmount(statement.amountDue.asCurrency),
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
                    ? context.l10n.payStatusPaid
                    : statement.isOverdue
                        ? context.l10n.billingOverdue
                        : context.l10n.billingStatusDue,
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
          _Row(
              label: context.l10n.billingTotalAmountDue,
              value: statement.amountDue.asCurrency),
          if (statement.minimumDue > 0) ...[
            AppSpacing.vGapSm,
            _Row(
                label: context.l10n.creditMinimumDue,
                value: statement.minimumDue.asCurrency),
          ],
          AppSpacing.vGapSm,
          _Row(
              label: context.l10n.creditDueDate,
              value: DateFormat('d MMMM yyyy').format(statement.dueDate)),
          AppSpacing.vGapSm,
          _Row(
              label: context.l10n.billingGenerated,
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
