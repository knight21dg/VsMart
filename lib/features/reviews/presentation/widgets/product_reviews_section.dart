import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < rating.round();
        return Icon(
          filled ? Icons.star_rounded : Icons.star_border_rounded,
          size: size,
          color: c,
        );
      }),
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
            Text('Ratings & Reviews', style: AppTypography.titleLarge),
            VSOutlinedButton(
              label: 'Write a Review',
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
              '${summary.count} '
              '${summary.count == 1 ? 'review' : 'reviews'}',
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
            'No reviews yet — be the first',
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
              "Couldn't load reviews.",
              style:
                  AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
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
      context.showSnack('Please pick a star rating', isError: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref.read(reviewsDataSourceProvider).postReview(
            productId: widget.productId,
            rating: _rating,
            title: _titleController.text.trim(),
            body: _bodyController.text.trim(),
          );
      ref.invalidate(productReviewsProvider(widget.productId));
      if (!mounted) return;
      Navigator.of(context).pop();
      context.showSnack('Thanks for your review!');
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      context.showSnack('Could not submit review. Please try again.',
          isError: true);
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
          Text('Write a Review', style: AppTypography.headlineSmall),
          AppSpacing.vGapLg,
          Text('Your rating', style: AppTypography.labelLarge),
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
            decoration: const InputDecoration(
              labelText: 'Title (optional)',
              hintText: 'Summarise your experience',
            ),
          ),
          AppSpacing.vGapMd,
          TextField(
            controller: _bodyController,
            enabled: !_submitting,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Your review (optional)',
              hintText: 'What did you like or dislike?',
              alignLabelWithHint: true,
            ),
          ),
          AppSpacing.vGapLg,
          VSButton(
            label: 'Submit Review',
            isLoading: _submitting,
            onPressed: _submitting ? null : _submit,
          ),
        ],
      ),
    );
  }
}
