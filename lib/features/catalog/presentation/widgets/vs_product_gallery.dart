import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';

/// Swipeable product image gallery with a page indicator and a fullscreen,
/// zoomable preview. Falls back to a branded placeholder when there are no
/// images (e.g. fixtures).
class VSProductGallery extends StatefulWidget {
  const VSProductGallery({super.key, required this.images});

  final List<String> images;

  @override
  State<VSProductGallery> createState() => _VSProductGalleryState();
}

class _VSProductGalleryState extends State<VSProductGallery> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openFullscreen(String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: AppColors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: VSNetworkImage(url: url, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: AppSpacing.lg,
              right: AppSpacing.lg,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.of(ctx).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    if (widget.images.isEmpty) {
      return AspectRatio(
        aspectRatio: 1,
        child: Container(
          width: double.infinity,
          color: vs.brandTint.withValues(alpha: 0.4),
          alignment: Alignment.center,
          child: Icon(Icons.shopping_basket_rounded,
              size: 96, color: AppColors.vsGreen.withValues(alpha: 0.6)),
        ),
      );
    }
    return Column(
      children: [
        // Square (1:1) product image card.
        AspectRatio(
          aspectRatio: 1,
          child: PageView.builder(
            controller: _controller,
            onPageChanged: (i) => setState(() => _page = i),
            itemCount: widget.images.length,
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => _openFullscreen(widget.images[i]),
              child: VSNetworkImage(url: widget.images[i], fit: BoxFit.cover),
            ),
          ),
        ),
        if (widget.images.length > 1) ...[
          AppSpacing.vGapSm,
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.images.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  height: 6,
                  width: i == _page ? 18 : 6,
                  decoration: BoxDecoration(
                    color: i == _page ? vs.brand : vs.border,
                    borderRadius: AppRadius.brPill,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
