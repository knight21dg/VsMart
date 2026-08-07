import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps a tappable child with a quick press "squish" scale and a haptic tick —
/// the micro-interaction used for ADD buttons, chips and CTAs.
class VSTapScale extends StatefulWidget {
  const VSTapScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.92,
    this.haptic = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool haptic;

  @override
  State<VSTapScale> createState() => _VSTapScaleState();
}

class _VSTapScaleState extends State<VSTapScale> {
  double _scale = 1;

  void _set(double v) {
    if (widget.onTap == null) return;
    setState(() => _scale = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _set(widget.scale),
      onTapUp: (_) => _set(1),
      onTapCancel: () => _set(1),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap!();
            },
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
