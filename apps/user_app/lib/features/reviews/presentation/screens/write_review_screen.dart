import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/app_error_presenter.dart';
import '../../../../core/errors/error_handler.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../providers/reviews_providers.dart';

/// Standalone full-screen "write a review" flow. The primary path is the modal
/// sheet inside [ProductReviewsSection]; this screen offers the same form for
/// deep-links or routes that need a dedicated page.
class WriteReviewScreen extends ConsumerStatefulWidget {
  const WriteReviewScreen({super.key, required this.productId, this.productName});

  final String productId;
  final String? productName;

  @override
  ConsumerState<WriteReviewScreen> createState() => _WriteReviewScreenState();
}

class _WriteReviewScreenState extends ConsumerState<WriteReviewScreen> {
  static const _maxBodyLength = 1000;

  int _rating = 5;
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating < 1) {
      context.showSnack(context.l10n.reviewsPickRating, isError: true);
      return;
    }
    final body = _bodyController.text.trim();
    if (body.length > _maxBodyLength) {
      context.showSnack(
        context.l10n.reviewsTooLong(_maxBodyLength),
        isError: true,
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(reviewsDataSourceProvider).postReview(
            productId: widget.productId,
            rating: _rating,
            title: _titleController.text.trim(),
            body: body,
          );
      ref.invalidate(productReviewsProvider(widget.productId));
      if (!mounted) return;
      Navigator.of(context).pop(true);
      context.showSnack(context.l10n.reviewsThanks);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      // Surface the real backend cause (e.g. "already reviewed") through the
      // actionable presenter instead of a generic snackbar.
      presentFailure(context, ref, ErrorHandler.handle(e), onRetry: _submit);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.reviewsWriteReview)),
      body: ListView(
        padding: AppSpacing.screen,
        children: [
          if (widget.productName != null) ...[
            Text(widget.productName!, style: AppTypography.titleLarge),
            AppSpacing.vGapLg,
          ],
          Text(context.l10n.reviewsYourRating, style: AppTypography.labelLarge),
          AppSpacing.vGapSm,
          Row(
            children: List.generate(5, (i) {
              final star = i + 1;
              final filled = star <= _rating;
              return IconButton(
                onPressed:
                    _submitting ? null : () => setState(() => _rating = star),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                iconSize: 40,
                icon: Icon(
                  filled ? Icons.star_rounded : Icons.star_border_rounded,
                  color: vs.offer,
                ),
              );
            }),
          ),
          AppSpacing.vGapLg,
          TextField(
            controller: _titleController,
            enabled: !_submitting,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: context.l10n.reviewsTitleOptional,
              hintText: context.l10n.reviewsSummarise,
            ),
          ),
          AppSpacing.vGapMd,
          TextField(
            controller: _bodyController,
            enabled: !_submitting,
            minLines: 4,
            maxLines: 8,
            maxLength: _maxBodyLength,
            decoration: InputDecoration(
              labelText: context.l10n.reviewsYourReview,
              hintText: context.l10n.reviewsLikeDislike,
              alignLabelWithHint: true,
            ),
          ),
          AppSpacing.vGapXl,
          VSButton(
            label: context.l10n.reviewsSubmitReview,
            isLoading: _submitting,
            onPressed: _submitting ? null : _submit,
          ),
        ],
      ),
    );
  }
}
