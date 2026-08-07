import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/app_error_presenter.dart';
import '../../../../core/errors/error_handler.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../data/reviews_data.dart';
import '../providers/reviews_providers.dart';

/// Row of 1..5 stars reflecting [rating] out of 5. Read-only display helper.
class _StarRow extends StatelessWidget {
  const _StarRow({required this.rating, this.size = 16});

  final num rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.vsColors.offer;
    // Display-only: announce the whole row as one value instead of five icons.
    return Semantics(
      label: context.l10n.searchRating,
      value: context.l10n.reviewsRatingValue(rating.round()),
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (i) {
            final filled = i < rating.round();
            return Icon(
              filled ? Icons.star_rounded : Icons.star_border_rounded,
              size: size,
              color: c,
            );
          }),
        ),
      ),
    );
  }
}

/// Embeddable product reviews block: summary header, a "Write a Review" CTA
/// (modal bottom sheet), and the list of reviews. Handles loading / empty /
/// error states inline — never throws.
class ProductReviewsSection extends ConsumerWidget {
  const ProductReviewsSection({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(productReviewsProvider(productId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(context.l10n.reviewsTitle, style: AppTypography.titleLarge),
            VSOutlinedButton(
              label: context.l10n.reviewsWriteReview,
              icon: Icons.rate_review_outlined,
              isExpanded: false,
              onPressed: () => _openWriteSheet(context, ref),
            ),
          ],
        ),
        AppSpacing.vGapMd,
        async.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(
              child: SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          ),
          error: (_, __) => _InlineError(
            onRetry: () => ref.invalidate(productReviewsProvider(productId)),
          ),
          data: (data) => _ReviewsBody(data: data),
        ),
      ],
    );
  }

  void _openWriteSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _WriteReviewSheet(productId: productId),
    );
  }
}

class _ReviewsBody extends StatelessWidget {
  const _ReviewsBody({required this.data});

  final ProductReviews data;

  @override
  Widget build(BuildContext context) {
    if (data.reviews.isEmpty && data.summary.count == 0) {
      return const _EmptyReviews();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryHeader(summary: data.summary),
        if (data.reviews.isNotEmpty) ...[
          const Divider(height: AppSpacing.xxl),
          ...List.generate(data.reviews.length, (i) {
            final r = data.reviews[i];
            return Padding(
              padding: EdgeInsets.only(
                bottom: i == data.reviews.length - 1 ? 0 : AppSpacing.lg,
              ),
              child: _ReviewTile(review: r),
            );
          }),
        ],
      ],
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.summary});

  final ReviewSummary summary;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              summary.average.toStringAsFixed(1),
              style: AppTypography.displayMedium,
            ),
            AppSpacing.vGapXs,
            _StarRow(rating: summary.average, size: 18),
            AppSpacing.vGapXs,
            Text(
              context.l10n.reviewsCount(summary.count),
              style: AppTypography.bodySmall.copyWith(color: vs.textSecondary),
            ),
          ],
        ),
        AppSpacing.hGapLg,
        Expanded(
          child: Column(
            children: [
              for (var star = 5; star >= 1; star--)
                _DistributionBar(
                  star: star,
                  count: summary.countFor(star),
                  total: summary.count,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DistributionBar extends StatelessWidget {
  const _DistributionBar({
    required this.star,
    required this.count,
    required this.total,
  });

  final int star;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final fraction = total == 0 ? 0.0 : (count / total).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            child: Text(
              '$star',
              textAlign: TextAlign.end,
              style: AppTypography.labelSmall.copyWith(color: vs.textSecondary),
            ),
          ),
          AppSpacing.hGapSm,
          Icon(Icons.star_rounded, size: 12, color: vs.offer),
          AppSpacing.hGapSm,
          Expanded(
            child: ClipRRect(
              borderRadius: AppRadius.brPill,
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 6,
                backgroundColor: vs.border,
                valueColor: AlwaysStoppedAnimation(vs.offer),
              ),
            ),
          ),
          AppSpacing.hGapSm,
          SizedBox(
            width: 24,
            child: Text(
              '$count',
              textAlign: TextAlign.end,
              style: AppTypography.labelSmall.copyWith(color: vs.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});

  final Review review;

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                review.authorName,
                style: AppTypography.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _StarRow(rating: review.rating, size: 14),
          ],
        ),
        if (review.title.isNotEmpty) ...[
          AppSpacing.vGapXs,
          Text(review.title, style: AppTypography.labelLarge),
        ],
        if (review.body.isNotEmpty) ...[
          AppSpacing.vGapXs,
          Text(
            review.body,
            style: AppTypography.bodyMedium
                .copyWith(color: vs.textSecondary, height: 1.5),
          ),
        ],
        AppSpacing.vGapXs,
        Text(
          _formatDate(review.createdAt),
          style: AppTypography.labelSmall.copyWith(color: vs.textSecondary),
        ),
      ],
    );
  }
}

class _EmptyReviews extends StatelessWidget {
  const _EmptyReviews();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xl,
        horizontal: AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: vs.offerTint,
        borderRadius: AppRadius.brLg,
      ),
      child: Column(
        children: [
          Icon(Icons.reviews_outlined, size: 36, color: vs.offer),
          AppSpacing.vGapSm,
          Text(
            context.l10n.reviewsNoneYet,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.lg,
        horizontal: AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: vs.dangerTint,
        borderRadius: AppRadius.brLg,
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 20, color: vs.danger),
          AppSpacing.hGapMd,
          Expanded(
            child: Text(
              context.l10n.commonSomethingWentWrong,
              style:
                  AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(context.l10n.commonRetry)),
        ],
      ),
    );
  }
}

/// Modal bottom sheet: star selector + title + body + submit.
class _WriteReviewSheet extends ConsumerStatefulWidget {
  const _WriteReviewSheet({required this.productId});

  final String productId;

  @override
  ConsumerState<_WriteReviewSheet> createState() => _WriteReviewSheetState();
}

class _WriteReviewSheetState extends ConsumerState<_WriteReviewSheet> {
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
      Navigator.of(context).pop();
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
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.sm,
        bottom: context.viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.reviewsWriteReview,
              style: AppTypography.headlineSmall),
          AppSpacing.vGapLg,
          Text(context.l10n.reviewsYourRating, style: AppTypography.labelLarge),
          AppSpacing.vGapSm,
          Row(
            children: List.generate(5, (i) {
              final star = i + 1;
              final filled = star <= _rating;
              return IconButton(
                onPressed: _submitting
                    ? null
                    : () => setState(() => _rating = star),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                iconSize: 36,
                tooltip: context.l10n.reviewsRateStars(star),
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
            minLines: 3,
            maxLines: 6,
            maxLength: _maxBodyLength,
            decoration: InputDecoration(
              labelText: context.l10n.reviewsYourReview,
              hintText: context.l10n.reviewsLikeDislike,
              alignLabelWithHint: true,
            ),
          ),
          AppSpacing.vGapLg,
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
