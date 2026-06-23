import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../app/theme/app_theme.dart';
import '../extensions/context_extensions.dart';

/// Wraps any widget in a themed shimmer effect for loading states.
class VSShimmer extends StatelessWidget {
  const VSShimmer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Shimmer.fromColors(
      baseColor: vs.shimmerBase,
      highlightColor: vs.shimmerHighlight,
      child: child,
    );
  }
}

/// A single shimmering block, useful for composing skeleton layouts.
class VSShimmerBox extends StatelessWidget {
  const VSShimmerBox({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius = AppRadius.brSm,
  });

  final double? width;
  final double height;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return VSShimmer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: context.vsColors.shimmerBase,
          borderRadius: borderRadius,
        ),
      ),
    );
  }
}
