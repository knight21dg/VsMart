import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_theme.dart';
import '../animations/cart_anim.dart';
import '../extensions/context_extensions.dart';
import '../extensions/num_extensions.dart';
import 'vs_network_image.dart';
import 'vs_tap_scale.dart';

/// Reusable grocery product card in a quick-commerce style: an edge-to-edge
/// image with a pack-size pill and a floating ADD control overlaid on it, then
/// price (with MRP strikethrough), name and rating below.
///
/// The image takes the space above a fixed info block, so every card is the
/// same size in a grid/rail. Adding to cart flies the product image into the
/// cart icon (see [CartAnim]).
class VSProductCard extends StatefulWidget {
  const VSProductCard({
    super.key,
    required this.name,
    required this.price,
    this.imageUrl,
    this.mrp,
    this.unitLabel,
    this.rating,
    this.reviews = 0,
    this.inWishlist = false,
    this.outOfStock = false,
    this.quantityInCart = 0,
    this.onTap,
    this.onAdd,
    this.onIncrement,
    this.onDecrement,
    this.onWishlistTap,
    this.heroTag,
  });

  final String name;
  final num price;
  final String? imageUrl;
  final num? mrp;
  final String? unitLabel;
  final double? rating;
  final int reviews;
  final bool inWishlist;
  final bool outOfStock;
  final int quantityInCart;
  final VoidCallback? onTap;
  final VoidCallback? onAdd;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;
  final VoidCallback? onWishlistTap;

  /// When set, the product image is a [Hero] with this tag so it morphs into the
  /// product overlay on open (and back on close).
  final String? heroTag;

  @override
  State<VSProductCard> createState() => _VSProductCardState();
}

class _VSProductCardState extends State<VSProductCard> {
  final GlobalKey _imageKey = GlobalKey();

  void _handleAdd() {
    CartAnim.fly(context, sourceKey: _imageKey, imageUrl: widget.imageUrl);
    widget.onAdd?.call();
  }

  Widget _maybeHero(Widget child) {
    final tag = widget.heroTag;
    if (tag == null) return child;
    return Hero(
      tag: tag,
      // Fly the already-cached card image during the flight so the FIRST open
      // morphs cleanly instead of fading in (the destination decodes after).
      flightShuttleBuilder: (_, __, ___, ____, _____) => VSNetworkImage(
        url: widget.imageUrl,
        fit: BoxFit.contain,
        borderRadius: AppRadius.brSm,
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final discount =
        widget.mrp != null ? widget.price.discountPercentFrom(widget.mrp!) : 0;
    final imageBg = vs.border.withValues(alpha: 0.30);

    return Material(
      color: context.colors.surface,
      borderRadius: AppRadius.brLg,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: AppRadius.brLg,
            border: Border.all(color: vs.border),
            boxShadow: AppShadows.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- Image with overlays ----
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        key: _imageKey,
                        color: imageBg,
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: _maybeHero(
                          Opacity(
                            opacity: widget.outOfStock ? 0.45 : 1,
                            child: VSNetworkImage(
                              url: widget.imageUrl,
                              fit: BoxFit.contain,
                              borderRadius: AppRadius.brSm,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (discount > 0 && !widget.outOfStock)
                      Positioned(
                        top: AppSpacing.xs,
                        left: AppSpacing.xs,
                        child: _Badge(label: '$discount% OFF', color: vs.offer),
                      ),
                    if (widget.outOfStock)
                      Positioned(
                        top: AppSpacing.xs,
                        left: AppSpacing.xs,
                        child: _Badge(
                            label: 'OUT OF STOCK', color: vs.textSecondary),
                      ),
                    if (widget.onWishlistTap != null)
                      Positioned(
                        top: AppSpacing.xs,
                        right: AppSpacing.xs,
                        child: _WishlistButton(
                          active: widget.inWishlist,
                          onTap: widget.onWishlistTap!,
                        ),
                      ),
                    if (widget.unitLabel != null &&
                        widget.unitLabel!.trim().isNotEmpty &&
                        widget.unitLabel != 'Each')
                      Positioned(
                        left: AppSpacing.xs,
                        bottom: AppSpacing.xs,
                        child: _PackPill(label: widget.unitLabel!),
                      ),
                    Positioned(
                      right: AppSpacing.xs,
                      bottom: AppSpacing.xs,
                      child: _CartControl(
                        quantity: widget.quantityInCart,
                        outOfStock: widget.outOfStock,
                        onAdd: widget.onAdd == null ? null : _handleAdd,
                        onIncrement: widget.onIncrement,
                        onDecrement: widget.onDecrement,
                      ),
                    ),
                  ],
                ),
              ),
              // ---- Info ----
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(widget.price.asCurrency,
                            style: AppTypography.priceMedium),
                        if (widget.mrp != null && discount > 0) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Flexible(
                            child: Text(
                              widget.mrp!.asCurrency,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodySmall.copyWith(
                                color: vs.textSecondary,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    // Fixed height (2 lines) so every card is the same size.
                    SizedBox(
                      height: 40,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: Text(
                          widget.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.titleMedium,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    SizedBox(
                      height: 20,
                      child: widget.rating != null && widget.rating! > 0
                          ? _Rating(rating: widget.rating!, reviews: widget.reviews)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: AppRadius.brSm),
      child: Text(label,
          style: AppTypography.labelSmall.copyWith(color: AppColors.white)),
    );
  }
}

/// Pack-size pill overlaid on the image (e.g. "700 ml", "1 kg"). Kept compact
/// (small, tablet-friendly) so it never crowds the card image.
class _PackPill extends StatelessWidget {
  const _PackPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: context.colors.surface.withValues(alpha: 0.92),
        borderRadius: AppRadius.brXs,
        border: Border.all(color: vs.border),
      ),
      child: Text(label,
          style: AppTypography.labelSmall.copyWith(
            color: vs.textSecondary,
            fontSize: 9,
            height: 1.1,
          )),
    );
  }
}

class _WishlistButton extends StatelessWidget {
  const _WishlistButton({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return VSTapScale(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // Slightly translucent so it reads cleanly over real product photos.
          color: context.colors.surface.withValues(alpha: 0.92),
          shape: BoxShape.circle,
          border: Border.all(color: vs.border),
        ),
        child: Icon(
          active ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          size: 18,
          color: active ? vs.danger : vs.textSecondary,
        ),
      ),
    );
  }
}

class _Rating extends StatelessWidget {
  const _Rating({required this.rating, required this.reviews});

  final double rating;
  final int reviews;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: vs.success.withValues(alpha: 0.14),
            borderRadius: AppRadius.brXs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(rating.toStringAsFixed(1),
                  style: AppTypography.labelSmall.copyWith(color: vs.success)),
              const SizedBox(width: 2),
              Icon(Icons.star_rounded, size: 11, color: vs.success),
            ],
          ),
        ),
        if (reviews > 0) ...[
          const SizedBox(width: 4),
          Flexible(
            child: Text('($reviews)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    AppTypography.labelSmall.copyWith(color: vs.textSecondary)),
          ),
        ],
      ],
    );
  }
}

/// The floating ADD button / quantity stepper overlaid on the image bottom-right.
class _CartControl extends StatelessWidget {
  const _CartControl({
    required this.quantity,
    required this.outOfStock,
    this.onAdd,
    this.onIncrement,
    this.onDecrement,
  });

  final int quantity;
  final bool outOfStock;
  final VoidCallback? onAdd;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;

    if (outOfStock) return const SizedBox.shrink();

    // Animate between the ADD pill and the quantity stepper.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, anim) =>
          ScaleTransition(scale: anim, child: child),
      child: quantity <= 0
          ? VSTapScale(
              key: const ValueKey('add'),
              onTap: onAdd,
              child: Container(
                width: 46,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: vs.brand,
                  borderRadius: AppRadius.brMd,
                  boxShadow: AppShadows.sm,
                ),
                child: const Icon(Icons.add_rounded,
                    size: 26, color: AppColors.white),
              ),
            )
          : Container(
              key: const ValueKey('stepper'),
              height: 38,
              decoration: BoxDecoration(
                color: vs.brand,
                borderRadius: AppRadius.brMd,
                boxShadow: AppShadows.sm,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StepIcon(icon: Icons.remove_rounded, onTap: onDecrement),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                    child: Text('$quantity',
                        style: AppTypography.titleMedium
                            .copyWith(color: AppColors.white)),
                  ),
                  _StepIcon(icon: Icons.add_rounded, onTap: onIncrement),
                ],
              ),
            ),
    );
  }
}

class _StepIcon extends StatelessWidget {
  const _StepIcon({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      child: SizedBox(
        height: 38,
        width: 34,
        child: Icon(icon, size: 20, color: AppColors.white),
      ),
    );
  }
}
