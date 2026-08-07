import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../cart/presentation/providers/cart_providers.dart';
import '../../domain/entities/reorder_line.dart';
import '../providers/order_providers.dart';

/// Reviews a reorder before it touches the cart, and adds it on confirm.
///
/// Reorder used to mutate the cart on a single tap. Both previous implementations
/// were also wrong about *what* they added: one re-fetched each product and dropped
/// the pack the customer had actually bought, the other rebuilt lines from the
/// ORDER's historical prices — so a basket could silently come back at last month's
/// prices, or as a different SKU.
///
/// Returns true when items were added.
Future<bool> showReorderSheet(
  BuildContext context, {
  required String orderCode,
}) async {
  final added = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReorderSheet(orderCode: orderCode),
  );
  return added ?? false;
}

class _ReorderSheet extends ConsumerStatefulWidget {
  const _ReorderSheet({required this.orderCode});

  final String orderCode;

  @override
  ConsumerState<_ReorderSheet> createState() => _ReorderSheetState();
}

class _ReorderSheetState extends ConsumerState<_ReorderSheet> {
  bool _adding = false;

  Future<void> _add(ReorderPlan plan) async {
    setState(() => _adding = true);
    final cart = ref.read(cartControllerProvider.notifier);
    // The server already decided what's available and at what price; the client
    // just applies it. No per-item fetch, no per-item failure to swallow.
    for (final line in plan.available) {
      await cart.add(line.toCartItem());
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final planAsync = ref.watch(reorderPreviewProvider(widget.orderCode));

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _Grabber(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(context.l10n.reorderSheetTitle,
                    style: AppTypography.titleLarge),
              ),
            ),
            AppSpacing.vGapSm,
            Expanded(
              child: planAsync.when(
                loading: () => const VSLoadingView(),
                error: (error, _) => Padding(
                  padding: AppSpacing.screen,
                  child: VSErrorView(
                    failure: error is Failure ? error : null,
                    onRetry: () => ref.invalidate(
                        reorderPreviewProvider(widget.orderCode)),
                  ),
                ),
                data: (plan) => _PlanBody(plan: plan, controller: controller),
              ),
            ),
            planAsync.maybeWhen(
              data: (plan) => SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                      AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
                  child: plan.hasAnythingToAdd
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(context.l10n.reorderPricesMayHaveChanged,
                                    style: AppTypography.bodySmall
                                        .copyWith(color: vs.textSecondary)),
                                Text(plan.total.asCurrency,
                                    style: AppTypography.titleMedium),
                              ],
                            ),
                            AppSpacing.vGapSm,
                            VSButton(
                              label: context.l10n
                                  .reorderAddAll(plan.available.length),
                              isLoading: _adding,
                              onPressed: _adding ? null : () => _add(plan),
                            ),
                          ],
                        )
                      : Text(
                          context.l10n.reorderNothingAvailable,
                          textAlign: TextAlign.center,
                          style: AppTypography.bodyMedium
                              .copyWith(color: vs.textSecondary),
                        ),
                ),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanBody extends StatelessWidget {
  const _PlanBody({required this.plan, required this.controller});

  final ReorderPlan plan;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    if (plan.isEmpty) {
      return Center(
        child: Text(context.l10n.reorderNothingAvailable,
            style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary)),
      );
    }
    return ListView(
      controller: controller,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      children: [
        for (final line in plan.available) _LineRow(line: line),
        if (plan.unavailable.isNotEmpty) ...[
          AppSpacing.vGapMd,
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: vs.textSecondary),
              AppSpacing.hGapSm,
              Text(context.l10n.reorderUnavailableHeading,
                  style: AppTypography.labelLarge
                      .copyWith(color: vs.textSecondary)),
            ],
          ),
          AppSpacing.vGapSm,
          for (final line in plan.unavailable) _LineRow(line: line),
        ],
        AppSpacing.vGapMd,
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line});

  final ReorderLine line;

  String _reasonLabel(BuildContext context) => switch (line.reason) {
        ReorderUnavailableReason.discontinued =>
          context.l10n.reorderDiscontinued,
        _ => context.l10n.reorderOutOfStock,
      };

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final dimmed = !line.available;
    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: AppRadius.brSm,
              child: SizedBox(
                height: 44,
                width: 44,
                child: (line.imageUrl ?? '').isEmpty
                    ? Container(
                        color: vs.brandTint,
                        child: Icon(Icons.shopping_basket_rounded,
                            size: 20, color: vs.brand),
                      )
                    : VSNetworkImage(url: line.imageUrl!, fit: BoxFit.cover),
              ),
            ),
            AppSpacing.hGapMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMedium),
                  Text(
                    dimmed ? _reasonLabel(context) : '${line.quantity} × ${line.unit}',
                    style: AppTypography.bodySmall.copyWith(
                      color: dimmed ? vs.danger : vs.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (!dimmed)
              Text(line.lineTotal.asCurrency,
                  style: AppTypography.labelLarge),
          ],
        ),
      ),
    );
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: context.vsColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}
