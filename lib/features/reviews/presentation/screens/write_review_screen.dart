import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
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
      Navigator.of(context).pop(true);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Write a Review')),
      body: ListView(
        padding: AppSpacing.screen,
        children: [
          if (widget.productName != null) ...[
            Text(widget.productName!, style: AppTypography.titleLarge),
            AppSpacing.vGapLg,
          ],
          Text('Your rating', style: AppTypography.labelLarge),
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
            decoration: const InputDecoration(
              labelText: 'Title (optional)',
              hintText: 'Summarise your experience',
            ),
          ),
          AppSpacing.vGapMd,
          TextField(
            controller: _bodyController,
            enabled: !_submitting,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Your review (optional)',
              hintText: 'What did you like or dislike?',
              alignLabelWithHint: true,
            ),
          ),
          AppSpacing.vGapXl,
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
