import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_theme.dart';
import '../widgets/vs_network_image.dart';

/// Coordinates the "fly to cart" animation and the cart-icon bump/ripple.
///
/// The cart icon registers itself (its position key + a bump callback). Any
/// "add to cart" action calls [fly] with the source widget/position; a small
/// product image arcs into the cart icon, then the icon bumps with haptics.
class CartAnim {
  CartAnim._();

  /// Placed on the cart icon so [fly] knows where to land.
  static final GlobalKey targetKey = GlobalKey();

  static final Set<VoidCallback> _landedListeners = <VoidCallback>{};

  /// Subscribe to the moment a flown product lands in the cart. The cart icon
  /// and the floating cart pill both ripple/bump on this signal — i.e. at the
  /// END of the fly arc, not when the item is first tapped.
  static void registerTarget(VoidCallback onLanded) =>
      _landedListeners.add(onLanded);
  static void clearTarget(VoidCallback onLanded) =>
      _landedListeners.remove(onLanded);

  static Offset? _centerOf(GlobalKey? key) {
    final ctx = key?.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  /// Animate a product flying from [sourceKey]/[sourceCenter] into the cart.
  static void fly(
    BuildContext context, {
    GlobalKey? sourceKey,
    Offset? sourceCenter,
    String? imageUrl,
    IconData icon = Icons.shopping_bag_rounded,
  }) {
    HapticFeedback.lightImpact();

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final start = sourceCenter ?? _centerOf(sourceKey);
    final end = _centerOf(targetKey);

    // If we can't resolve geometry, still give feedback + bump.
    if (overlay == null || start == null || end == null) {
      _bump();
      return;
    }

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _FlyingItem(
        start: start,
        end: end,
        imageUrl: imageUrl,
        icon: icon,
        onDone: () {
          entry.remove();
          _bump();
        },
      ),
    );
    overlay.insert(entry);
  }

  static void _bump() {
    HapticFeedback.mediumImpact();
    for (final listener in _landedListeners.toList()) {
      listener();
    }
  }
}

/// The product chip that arcs from the source to the cart along a bezier curve,
/// shrinking and fading as it lands.
class _FlyingItem extends StatefulWidget {
  const _FlyingItem({
    required this.start,
    required this.end,
    required this.onDone,
    this.imageUrl,
    required this.icon,
  });

  final Offset start;
  final Offset end;
  final VoidCallback onDone;
  final String? imageUrl;
  final IconData icon;

  @override
  State<_FlyingItem> createState() => _FlyingItemState();
}

class _FlyingItemState extends State<_FlyingItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );

  late final Offset _control;
  static const double _size = 56;

  @override
  void initState() {
    super.initState();
    // Control point lifts the path into an arc before it dips to the cart.
    final dx = widget.start.dx + (widget.end.dx - widget.start.dx) * 0.25;
    final dy = math.min(widget.start.dy, widget.end.dy) - 90;
    _control = Offset(dx, dy);
    _c.forward();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Offset _bezier(double t) {
    final mt = 1 - t;
    return widget.start * (mt * mt) +
        _control * (2 * mt * t) +
        widget.end * (t * t);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeInCubic.transform(_c.value);
        final pos = _bezier(t);
        final scale = 1.0 - 0.62 * t;
        final opacity = t < 0.85 ? 1.0 : (1 - (t - 0.85) / 0.15);
        return Positioned(
          left: pos.dx - _size / 2,
          top: pos.dy - _size / 2,
          child: IgnorePointer(
            child: Opacity(
              opacity: opacity.clamp(0, 1),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: _size,
                  height: _size,
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    shape: BoxShape.circle,
                    boxShadow: AppShadows.md,
                    border: Border.all(
                        color: AppColors.vsGreen.withValues(alpha: 0.4),
                        width: 2),
                  ),
                  padding: const EdgeInsets.all(6),
                  child: (widget.imageUrl != null && widget.imageUrl!.isNotEmpty)
                      ? VSNetworkImage(
                          url: widget.imageUrl,
                          borderRadius: AppRadius.brPill,
                        )
                      : Icon(widget.icon, color: AppColors.vsGreen, size: 26),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
