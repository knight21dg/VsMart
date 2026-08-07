import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/app_error_presenter.dart';
import '../../../../core/errors/error_handler.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../providers/order_providers.dart';

/// "How did it go?" — the ONLY place VS Mart asks for a rating.
///
/// Products deliberately carry none (for groceries a star rating on milk tells
/// nobody anything); what's worth knowing is whether the delivery was good. The
/// backend raises the request the moment a delivery completes, so this card
/// simply hides itself until then, and lets the customer change their mind after.
class OrderFeedbackCard extends ConsumerStatefulWidget {
  const OrderFeedbackCard({super.key, required this.orderCode});

  final String orderCode;

  @override
  ConsumerState<OrderFeedbackCard> createState() => _OrderFeedbackCardState();
}

class _OrderFeedbackCardState extends ConsumerState<OrderFeedbackCard> {
  int _stars = 0;
  final _comment = TextEditingController();
  bool _busy = false;
  bool _editing = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_stars == 0) return;
    setState(() => _busy = true);
    try {
      await ref.read(orderRemoteDataSourceProvider).submitFeedback(
            widget.orderCode,
            rating: _stars,
            comment: _comment.text.trim(),
          );
      ref.invalidate(orderFeedbackProvider(widget.orderCode));
      if (!mounted) return;
      setState(() { _busy = false; _editing = false; });
      context.showSnack(context.l10n.ordersFeedbackThanks);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      presentFailure(context, ref, ErrorHandler.handle(e), onRetry: _submit);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final async = ref.watch(orderFeedbackProvider(widget.orderCode));
    final fb = async.valueOrNull;

    // Nothing to ask until the order is actually delivered.
    if (fb == null || !fb.available) return const SizedBox.shrink();

    // Already answered → show it back, with a way to change it.
    if (fb.rated && !_editing) {
      return _Shell(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.ordersYouRated, style: AppTypography.titleMedium),
                  AppSpacing.vGapXs,
                  _Stars(value: fb.rating ?? 0, onTap: null),
                  if (fb.feedback.isNotEmpty) ...[
                    AppSpacing.vGapXs,
                    Text(fb.feedback,
                        style: AppTypography.bodySmall
                            .copyWith(color: vs.textSecondary)),
                  ],
                ],
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                _editing = true;
                _stars = fb.rating ?? 0;
                _comment.text = fb.feedback;
              }),
              child: Text(context.l10n.commonChange),
            ),
          ],
        ),
      );
    }

    return _Shell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.ordersHowWasDelivery, style: AppTypography.titleMedium),
          AppSpacing.vGapXs,
          Text(
            fb.agentName == null
                ? context.l10n.ordersFeedbackHelps
                : context.l10n.ordersAgentDelivered(fb.agentName!),
            style: AppTypography.bodySmall.copyWith(color: vs.textSecondary),
          ),
          AppSpacing.vGapMd,
          _Stars(
            value: _stars,
            onTap: (v) {
              HapticFeedback.selectionClick();
              setState(() => _stars = v);
            },
          ),
          if (_stars > 0) ...[
            AppSpacing.vGapMd,
            VSTextField(
              controller: _comment,
              hint: context.l10n.ordersFeedbackHint,
              maxLines: 2,
            ),
            AppSpacing.vGapMd,
            VSButton(
              label: context.l10n.ordersSendFeedback,
              isLoading: _busy,
              onPressed: _busy ? null : _submit,
            ),
          ],
        ],
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: AppRadius.brMd,
          border: Border.all(color: context.vsColors.border),
        ),
        child: child,
      );
}

class _Stars extends StatelessWidget {
  const _Stars({required this.value, this.onTap});

  final int value;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 1; i <= 5; i++)
          GestureDetector(
            onTap: onTap == null ? null : () => onTap!(i),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(
                i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                size: onTap == null ? 20 : 34,
                color: i <= value
                    ? AppColors.warning
                    : context.vsColors.textSecondary,
                semanticLabel: context.l10n.ordersStarCount(i),
              ),
            ),
          ),
      ],
    );
  }
}
