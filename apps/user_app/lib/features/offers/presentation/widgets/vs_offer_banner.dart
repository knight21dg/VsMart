import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../domain/entities/offer.dart';

/// Promotional banner card. Renders the processed [Offer] image (WebP, DPR-aware)
/// with a legibility scrim and localized overlay text; falls back to a gradient
/// card for legacy banners that have no image.
///
/// The overlay is driven by the banner's own presentation fields:
/// [Offer.textTheme] (`light` / `dark` / `none`), [Offer.textPosition],
/// [Offer.accentColor] and [Offer.ctaText]. `none` suppresses the scrim and all
/// copy so artwork that already carries its message renders untouched.
class VSOfferBanner extends StatelessWidget {
  const VSOfferBanner({super.key, required this.offer, this.onTap});

  final Offer offer;
  final VoidCallback? onTap;

  // Rotate gradients so consecutive (image-less) banners read as distinct.
  static const _gradients = [
    AppColors.offerGradient,
    AppColors.creditGradient,
    AppColors.greenGradient,
  ];

  bool get _isDarkText => offer.textTheme == BannerTextTheme.dark;

  /// Primary copy colour for the chosen theme.
  Color get _fg => _isDarkText ? const Color(0xFF10141A) : AppColors.white;

  /// Accent for the CTA pill / badge, honouring the admin's colour override.
  Color _accent(BuildContext context) {
    final argb = offer.accentArgb;
    return argb != null ? Color(argb) : Theme.of(context).colorScheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
    final title = offer.localizedTitle(lang);
    final subtitle = offer.localizedSubtitle(lang);
    final cta = offer.localizedCta(lang);

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brXl,
      child: ClipRRect(
        borderRadius: AppRadius.brXl,
        child: offer.image != null
            ? _imageCard(context, title, subtitle, cta)
            : _gradientCard(context, title, subtitle, cta),
      ),
    );
  }

  Widget _imageCard(
      BuildContext context, String title, String subtitle, String cta) {
    final img = offer.image!;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final bare = offer.textTheme == BannerTextTheme.none;
    // The caller supplies the height (a fixed-height SizedBox), so fill it via the
    // Stack rather than an AspectRatio (which a tight-constraint parent ignores).
    return LayoutBuilder(
      builder: (context, c) {
        final url = img.best(c.maxWidth, dpr);
        if (url == null) {
          return _gradientCard(context, title, subtitle, cta); // no usable variant
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              // The server already stored this at the placement's exact ratio, so
              // cover is a no-op crop; the focal alignment only matters for legacy
              // images stored at the old universal 2:1.
              alignment: Alignment(img.focusX * 2 - 1, img.focusY * 2 - 1),
              placeholder: (_, __) => Container(color: AppColors.shimmerBase),
              // Plain gradient (no text) — the Stack's overlay below draws it once.
              errorWidget: (_, __, ___) => _plainGradient(),
            ),
            // Scrim for legibility. Skipped entirely when the artwork is bare.
            if (!bare) _scrim(),
            if (!bare)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: _overlay(context, title, subtitle, cta, onImage: true),
              ),
          ],
        );
      },
    );
  }

  /// Directional scrim matching the text theme and position — a bottom-anchored
  /// block only needs the bottom darkened, a centred one needs the middle.
  Widget _scrim() {
    final base = _isDarkText ? AppColors.white : Colors.black;
    final strong = base.withValues(alpha: _isDarkText ? 0.86 : 0.58);
    final (begin, end) = switch (offer.textPosition) {
      BannerTextPosition.topLeft => (Alignment.bottomCenter, Alignment.topCenter),
      BannerTextPosition.center => (Alignment.center, Alignment.center),
      _ => (Alignment.topCenter, Alignment.bottomCenter),
    };
    if (offer.textPosition == BannerTextPosition.center) {
      // A centred block reads best over an even wash rather than a directional ramp.
      return DecoratedBox(
        decoration: BoxDecoration(
          color: base.withValues(alpha: _isDarkText ? 0.6 : 0.38),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: begin,
          end: end,
          colors: [Colors.transparent, strong],
          stops: const [0.45, 1],
        ),
      ),
    );
  }

  Widget _plainGradient() {
    final gradient = _gradients[offer.id.hashCode.abs() % _gradients.length];
    return DecoratedBox(decoration: BoxDecoration(gradient: gradient));
  }

  Widget _gradientCard(
      BuildContext context, String title, String subtitle, String cta) {
    final gradient = _gradients[offer.id.hashCode.abs() % _gradients.length];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(gradient: gradient, borderRadius: AppRadius.brXl),
      // A gradient card has no artwork to speak for itself, so it always shows
      // its copy even when the banner asked for `none`.
      child: _overlay(context, title, subtitle, cta, onImage: false),
    );
  }

  Widget _overlay(BuildContext context, String title, String subtitle, String cta,
      {required bool onImage}) {
    // Gradient cards are always light-on-colour regardless of the chosen theme.
    final fg = onImage ? _fg : AppColors.white;
    final faint = fg.withValues(alpha: 0.9);
    final pos = offer.textPosition;
    final centred = pos == BannerTextPosition.bottomCenter ||
        pos == BannerTextPosition.center;

    final mainAxis = switch (pos) {
      BannerTextPosition.topLeft => MainAxisAlignment.start,
      BannerTextPosition.center => MainAxisAlignment.center,
      _ => MainAxisAlignment.end,
    };

    return Column(
      crossAxisAlignment:
          centred ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: onImage ? mainAxis : MainAxisAlignment.start,
      children: [
        if (offer.badge != null)
          _pill(
            offer.badge!,
            background: onImage
                ? _accent(context)
                : AppColors.white.withValues(alpha: 0.22),
            foreground: AppColors.white,
            radius: AppRadius.brSm,
          ),
        AppSpacing.vGapSm,
        Text(
          title,
          textAlign: centred ? TextAlign.center : TextAlign.start,
          style: AppTypography.headlineLarge.copyWith(color: fg),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            textAlign: centred ? TextAlign.center : TextAlign.start,
            style: AppTypography.bodyMedium.copyWith(color: faint),
          ),
        ],
        if (cta.isNotEmpty) ...[
          AppSpacing.vGapSm,
          _pill(
            cta,
            background: _accent(context),
            foreground: AppColors.white,
            radius: AppRadius.brPill,
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
        ] else if (offer.code != null) ...[
          AppSpacing.vGapSm,
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: fg.withValues(alpha: 0.18),
              borderRadius: AppRadius.brSm,
              border: Border.all(color: fg.withValues(alpha: 0.4)),
            ),
            child: Text(context.l10n.offersCodeLabel(offer.code!),
                style: AppTypography.labelMedium.copyWith(color: fg)),
          ),
        ],
      ],
    );
  }

  Widget _pill(
    String label, {
    required Color background,
    required Color foreground,
    required BorderRadius radius,
    double horizontal = AppSpacing.sm,
    double vertical = 2,
  }) =>
      Container(
        padding:
            EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical),
        decoration: BoxDecoration(color: background, borderRadius: radius),
        child: Text(label,
            style: AppTypography.labelSmall.copyWith(color: foreground)),
      );
}
