import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/theme/app_theme.dart';
import '../animations/cart_anim.dart';
import '../extensions/context_extensions.dart';

/// A single destination in [VSBottomNavigation]. Uses a custom SVG icon
/// (recolored for active/inactive) rather than a stock Material icon.
class VSNavItem {
  const VSNavItem({
    required this.asset,
    required this.label,
    this.isCart = false,
    this.badgeCount,
  });

  /// Path to the custom SVG icon (e.g. `assets/icons/nav_home.svg`).
  final String asset;
  final String label;

  /// The cart destination animates (bump + ripple) and is the fly-to-cart target.
  final bool isCart;
  final int? badgeCount;
}

/// VS Mart primary bottom navigation — custom icons, an active highlight pill,
/// and an animated cart that bumps when items land in it.
class VSBottomNavigation extends StatelessWidget {
  const VSBottomNavigation({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<VSNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: vs.border)),
        boxShadow: AppShadows.sm,
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: List.generate(items.length, (i) {
              final item = items[i];
              final selected = i == currentIndex;
              final color = selected ? vs.brand : vs.textSecondary;
              return Expanded(
                child: InkResponse(
                  onTap: () => onTap(i),
                  radius: 48,
                  highlightColor: AppColors.transparent,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
                        decoration: BoxDecoration(
                          color: selected
                              ? vs.brandTint.withValues(alpha: 0.6)
                              : AppColors.transparent,
                          borderRadius: AppRadius.brPill,
                        ),
                        child: item.isCart
                            ? _CartNavIcon(
                                asset: item.asset,
                                color: color,
                                badgeCount: item.badgeCount,
                              )
                            : _SvgIcon(asset: item.asset, color: color),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.label,
                        style: AppTypography.labelSmall.copyWith(
                          color: color,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _SvgIcon extends StatelessWidget {
  const _SvgIcon({required this.asset, required this.color});

  final String asset;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      asset,
      width: 24,
      height: 24,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}

/// Animated cart icon: registers as the fly-to-cart target and plays a
/// scale-bump + expanding ripple (with the count badge) when an item lands.
class _CartNavIcon extends StatefulWidget {
  const _CartNavIcon({
    required this.asset,
    required this.color,
    this.badgeCount,
  });

  final String asset;
  final Color color;
  final int? badgeCount;

  @override
  State<_CartNavIcon> createState() => _CartNavIconState();
}

class _CartNavIconState extends State<_CartNavIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );

  void _bump() {
    if (!mounted) return;
    _c.forward(from: 0);
  }

  @override
  void initState() {
    super.initState();
    CartAnim.registerTarget(_bump);
  }

  @override
  void dispose() {
    CartAnim.clearTarget(_bump);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final count = widget.badgeCount ?? 0;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final v = _c.value;
        final scale = 1 + 0.30 * math.sin(math.pi * v);
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            // Expanding ripple ring during a bump.
            if (v > 0 && v < 1)
              Container(
                width: 24 + 26 * v,
                height: 24 + 26 * v,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: vs.brand.withValues(alpha: 0.18 * (1 - v)),
                ),
              ),
            Transform.scale(scale: scale, child: child),
          ],
        );
      },
      child: SizedBox(
        key: CartAnim.targetKey,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            _SvgIcon(asset: widget.asset, color: widget.color),
            if (count > 0)
              Positioned(
                right: -8,
                top: -6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 16),
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    borderRadius: AppRadius.brPill,
                  ),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    textAlign: TextAlign.center,
                    style: AppTypography.labelSmall
                        .copyWith(color: AppColors.white, fontSize: 9),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
