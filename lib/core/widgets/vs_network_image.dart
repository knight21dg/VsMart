import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../extensions/context_extensions.dart';
import 'vs_shimmer.dart';

/// Cached network image with shimmer placeholder and graceful error fallback.
class VSNetworkImage extends StatelessWidget {
  const VSNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = AppRadius.brMd,
    this.fallbackIcon = Icons.image_outlined,
  });

  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius borderRadius;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final placeholder = VSShimmer(
      child: Container(
        width: width,
        height: height,
        color: context.vsColors.shimmerBase,
      ),
    );

    final error = Container(
      width: width,
      height: height,
      color: context.colors.surface,
      alignment: Alignment.center,
      child: Icon(fallbackIcon, color: context.vsColors.textSecondary),
    );

    final hasUrl = url != null && url!.isNotEmpty;
    // Bundled sample images ship as local assets (e.g. assets/images/...).
    final isAsset = hasUrl && url!.startsWith('assets/');

    return ClipRRect(
      borderRadius: borderRadius,
      child: !hasUrl
          ? error
          : isAsset
              ? Image.asset(
                  url!,
                  width: width,
                  height: height,
                  fit: fit,
                  errorBuilder: (_, __, ___) => error,
                )
              : CachedNetworkImage(
                  imageUrl: url!,
                  width: width,
                  height: height,
                  fit: fit,
                  placeholder: (_, __) => placeholder,
                  errorWidget: (_, __, ___) => error,
                ),
    );
  }
}
