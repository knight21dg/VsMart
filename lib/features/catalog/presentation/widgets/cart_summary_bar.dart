import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/animations/cart_anim.dart';
import '../../../../core/extensions/num_extensions.dart';

/// Floating green summary bar shown above catalog screens when the cart is
/// non-empty. Tapping it opens the cart. Adding an item plays a bump + ripple
/// so the pill visibly reacts when a product flies into it.
class CartSummaryBar extends StatefulWidget {
  const CartSummaryBar({
    super.key,
    required this.itemCount,
    required this.total,
    required this.onViewCart,
  });

  final int itemCount;
  final num total;
  final VoidCallback onViewCart;

  @override
  State<CartSummaryBar> createState() => _CartSummaryBarState();
}

class _CartSummaryBarState extends State<CartSummaryBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );

  late final Animation<double> _bump = TweenSequence<double>([
    TweenSequenceItem(
      tween:
          Tween(begin: 1.0, end: 1.14).chain(CurveTween(curve: Curves.easeOut)),
      weight: 35,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.14, end: 1.0)
          .chain(CurveTween(curve: Curves.elasticOut)),
      weight: 65,
    ),
  ]).animate(_ctrl);

  @override
  void initState() {
    super.initState();
    // Ripple exactly when a flown product LANDS in the cart (end of the arc),
    // not when the item is first tapped. CartAnim fires this on landing.
    CartAnim.registerTarget(_onLanded);
  }

  void _onLanded() {
    if (mounted) _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    CartAnim.clearTarget(_onLanded);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.itemCount <= 0) return const SizedBox.shrink();
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // Expanding ripple ring that pulses outward on each add.
              if (_ctrl.isAnimating)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Transform.scale(
                      scale: 1 + 0.22 * _ctrl.value,
                      child: Opacity(
                        opacity: (1 - _ctrl.value) * 0.6,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: AppRadius.brPill,
                            border:
                                Border.all(color: AppColors.vsGreen, width: 3),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Transform.scale(scale: _bump.value, child: child),
            ],
          );
        },
        child: _Pill(
          itemCount: widget.itemCount,
          total: widget.total,
          onViewCart: widget.onViewCart,
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.itemCount,
    required this.total,
    required this.onViewCart,
  });

  final int itemCount;
  final num total;
  final VoidCallback onViewCart;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.vsGreen,
      borderRadius: AppRadius.brPill,
      elevation: 8,
      shadowColor: AppColors.vsGreen.withValues(alpha: 0.5),
      child: InkWell(
        onTap: onViewCart,
        borderRadius: AppRadius.brPill,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shopping_basket_rounded,
                    color: AppColors.white, size: 20),
              ),
              AppSpacing.hGapMd,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$itemCount ${itemCount == 1 ? 'Item' : 'Items'}',
                      style: AppTypography.labelSmall.copyWith(
                          color: AppColors.white.withValues(alpha: 0.9))),
                  Text(total.asCurrency,
                      style: AppTypography.priceMedium
                          .copyWith(color: AppColors.white)),
                ],
              ),
              const Spacer(),
              Text('View Cart',
                  style: AppTypography.labelLarge
                      .copyWith(color: AppColors.white)),
              const SizedBox(width: AppSpacing.xs),
              const Icon(Icons.arrow_forward_rounded,
                  color: AppColors.white, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
