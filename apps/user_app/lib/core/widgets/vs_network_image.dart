import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/config/app_config.dart';
import '../../app/theme/app_theme.dart';
import '../../shared/providers/core_providers.dart';
import '../extensions/context_extensions.dart';
import '../network/media_auth.dart';
import 'vs_shimmer.dart';

/// Cached network image with shimmer placeholder and graceful error fallback.
///
/// For our own private, auth-gated media URLs (see [MediaAuth.isPrivateApiMedia]
/// — KYC docs, delivery POD, verification evidence, generic private assets) the
/// access token is attached as an `Authorization: Bearer` header so the image
/// loads. Public/catalog/avatar URLs take the normal no-auth path unchanged.
class VSNetworkImage extends ConsumerWidget {
  const VSNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = AppRadius.brMd,
    this.fallbackIcon = Icons.image_outlined,
    this.placeholderUrl,
    this.fadeInDuration = const Duration(milliseconds: 250),
  });

  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius borderRadius;
  final IconData fallbackIcon;

  /// An already-warm image (e.g. the listing thumbnail the user just tapped) to
  /// show INSTEAD of the shimmer while [url] resolves. When this is set and its
  /// bytes are in cache, the image appears immediately and cross-fades to [url]
  /// — so the user never sees a loading state on the first open, only the fade.
  final String? placeholderUrl;

  /// Cross-fade duration when the real image arrives.
  final Duration fadeInDuration;

  /// Resolve a possibly host-root-relative media path (e.g.
  /// `/api/v1/media/public/<id>/medium`, which is exactly what our catalog /
  /// banner / avatar endpoints return) to an absolute URL against the API
  /// origin. Absolute URLs, bundled `assets/...` paths, and null/empty pass
  /// through unchanged, so this is safe to apply to every url. Without it a
  /// relative path reaches `CachedNetworkImage` and always fails → blank tile.
  static String? _resolve(String? url) {
    if (url == null || url.isEmpty) return url;
    if (url.startsWith('assets/')) return url;
    return AppConfig.instance.assetUrl(url);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = _resolve(this.url);
    final placeholderUrl = _resolve(this.placeholderUrl);
    final shimmer = VSShimmer(
      child: Container(
        width: width,
        height: height,
        color: context.vsColors.shimmerBase,
      ),
    );

    // When a warm placeholder URL is supplied (and differs from the target),
    // render it as the loading state so a first open shows the cached image
    // instantly instead of a shimmer. It degrades to the shimmer if that image
    // isn't cached yet either.
    final hasPlaceholderUrl = placeholderUrl != null &&
        placeholderUrl.isNotEmpty &&
        placeholderUrl != url &&
        !placeholderUrl.startsWith('assets/');
    final Widget placeholder = hasPlaceholderUrl
        ? CachedNetworkImage(
            imageUrl: placeholderUrl,
            width: width,
            height: height,
            fit: fit,
            placeholder: (_, __) => shimmer,
            errorWidget: (_, __, ___) => shimmer,
          )
        : shimmer;

    final error = Container(
      width: width,
      height: height,
      color: context.colors.surface,
      alignment: Alignment.center,
      child: Icon(fallbackIcon, color: context.vsColors.textSecondary),
    );

    final hasUrl = url != null && url.isNotEmpty;
    // Bundled sample images ship as local assets (e.g. assets/images/...).
    final isAsset = hasUrl && url.startsWith('assets/');

    if (!hasUrl) {
      return ClipRRect(borderRadius: borderRadius, child: error);
    }
    if (isAsset) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: Image.asset(
          url,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) => error,
        ),
      );
    }

    // Private API media needs the bearer token; everything else loads as-is.
    final isPrivate = MediaAuth.isPrivateApiMedia(url);
    Map<String, String>? headers;
    if (isPrivate) {
      final token = ref.watch(accessTokenProvider).valueOrNull;
      // No token yet (loading or signed out): show the placeholder while the
      // token resolves rather than firing an un-authenticated request that
      // would 401. If there's genuinely no session, it stays a placeholder —
      // never a crash.
      if (token == null || token.isEmpty) {
        return ClipRRect(
          borderRadius: borderRadius,
          child: ref.watch(accessTokenProvider).hasError ? error : placeholder,
        );
      }
      headers = {'Authorization': 'Bearer $token'};
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: CachedNetworkImage(
        imageUrl: url,
        httpHeaders: headers,
        width: width,
        height: height,
        fit: fit,
        fadeInDuration: fadeInDuration,
        placeholder: (_, __) => placeholder,
        errorWidget: (_, __, ___) => error,
      ),
    );
  }
}
