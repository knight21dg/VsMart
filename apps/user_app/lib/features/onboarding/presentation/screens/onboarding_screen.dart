import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/providers/settings_provider.dart';

/// First-run onboarding carousel introducing groceries, credit, and the VS
/// score. Each slide carries its own accent so the flow feels dynamic; the hero
/// art parallaxes with the swipe. Marks onboarding complete and routes to login.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  /// Number of onboarding slides (kept in sync with [_buildSlides]).
  static const _slideCount = 3;

  /// Builds the localized slide copy for the active locale. Each slide owns an
  /// accent + gradient so the CTA, hero and dots recolor as you advance.
  List<_Slide> _buildSlides(AppLocalizations l10n, VSColors vs) => [
        _Slide(
          icon: Icons.local_shipping_rounded,
          caption: l10n.onboardingSlide1Caption,
          title: l10n.onboardingSlide1Title,
          subtitle: l10n.onboardingSlide1Body,
          accent: vs.brand,
          accentTint: vs.brandTint,
          gradient: AppColors.greenGradient,
        ),
        _Slide(
          icon: Icons.account_balance_wallet_rounded,
          caption: l10n.onboardingSlide2Caption,
          title: l10n.onboardingSlide2Title,
          subtitle: l10n.onboardingSlide2Body,
          accent: vs.trust,
          accentTint: vs.trustTint,
          gradient: AppColors.creditGradient,
        ),
        _Slide(
          icon: Icons.trending_up_rounded,
          caption: l10n.onboardingSlide3Caption,
          title: l10n.onboardingSlide3Title,
          subtitle: l10n.onboardingSlide3Body,
          accent: vs.offer,
          accentTint: vs.offerTint,
          gradient: AppColors.offerGradient,
        ),
      ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _page == _slideCount - 1;

  Future<void> _finish() async {
    await ref.read(onboardingSeenProvider.notifier).complete();
    // Ask for the app's permissions up front — location (delivery/serviceability),
    // notifications (order + delivery updates) and camera (KYC later) — BEFORE the
    // post-login serviceability check needs the GPS fix, so the user grants access
    // once here rather than being surprised by a system prompt mid-flow. Best
    // effort: onboarding never blocks on the outcome.
    await _requestStartupPermissions();
    if (!mounted) return;
    context.goNamed(RouteNames.login);
  }

  /// Requests the runtime permissions VS Mart uses, in one upfront batch. The OS
  /// shows each dialog in turn; a denial is fine — features degrade gracefully
  /// and the user can re-grant from settings later.
  Future<void> _requestStartupPermissions() async {
    try {
      await [
        Permission.location,
        Permission.notification,
        Permission.camera,
      ].request();
    } catch (_) {
      // Never let a permission plugin error stall first-run onboarding.
    }
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final slides = _buildSlides(context.l10n, vs);
    final active = slides[_page];

    return Scaffold(
      body: Stack(
        children: [
          // A soft top wash in the active slide's accent that cross-fades as the
          // page changes — gives each screen its own atmosphere.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            child: DecoratedBox(
              key: ValueKey(active.accent),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    active.accent.withValues(alpha: 0.10),
                    active.accent.withValues(alpha: 0.0),
                  ],
                  stops: const [0, 0.55],
                ),
              ),
              child: const SizedBox.expand(),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // ----- Top bar: wordmark + Skip -----
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xl, AppSpacing.md, AppSpacing.md, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('VS Mart',
                          style: AppTypography.headlineSmall
                              .copyWith(color: vs.brand)),
                      AnimatedOpacity(
                        opacity: _isLast ? 0 : 1,
                        duration: const Duration(milliseconds: 200),
                        child: TextButton(
                          onPressed: _isLast ? null : _finish,
                          style: TextButton.styleFrom(
                            foregroundColor: vs.textSecondary,
                            shape: const RoundedRectangleBorder(
                                borderRadius: AppRadius.brPill),
                          ),
                          child: Text(context.l10n.commonSkip,
                              style: AppTypography.labelLarge
                                  .copyWith(color: vs.textSecondary)),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: slides.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (_, i) => AnimatedBuilder(
                      animation: _controller,
                      builder: (context, __) {
                        // Distance of this page from the viewport centre, used
                        // for parallax + fade. Falls back to the integer page
                        // before the controller has dimensions.
                        final page = _controller.hasClients &&
                                _controller.position.hasContentDimensions
                            ? (_controller.page ?? _page.toDouble())
                            : _page.toDouble();
                        return _SlideView(slide: slides[i], delta: i - page);
                      },
                    ),
                  ),
                ),
                // ----- Page indicator -----
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < slides.length; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOut,
                        margin:
                            const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                        height: 7,
                        width: i == _page ? 26 : 7,
                        decoration: BoxDecoration(
                          color: i == _page
                              ? active.accent
                              : active.accent.withValues(alpha: 0.20),
                          borderRadius: AppRadius.brPill,
                        ),
                      ),
                  ],
                ),
                // ----- CTA -----
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.xl,
                      AppSpacing.xl, AppSpacing.xl, AppSpacing.lg),
                  child: _GradientCta(
                    label: _isLast
                        ? context.l10n.onboardingGetStarted
                        : context.l10n.commonNext,
                    gradient: active.gradient,
                    accent: active.accent,
                    onTap: _next,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Slide {
  const _Slide({
    required this.icon,
    required this.caption,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.accentTint,
    required this.gradient,
  });

  final IconData icon;
  final String caption;
  final String title;
  final String subtitle;
  final Color accent;
  final Color accentTint;
  final Gradient gradient;
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide, required this.delta});

  final _Slide slide;

  /// Signed distance (in pages) of this slide from the viewport centre.
  /// 0 = centred, ±1 = one page away. Drives the parallax + fade.
  final double delta;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    // Off-centre slides fade and drop slightly so the focused one pops.
    final t = (1 - delta.abs()).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 2),
          // Hero art parallaxes horizontally against the swipe.
          Transform.translate(
            offset: Offset(delta * -40, 0),
            child: Opacity(
              opacity: (0.35 + 0.65 * t).clamp(0.0, 1.0),
              child: _HeroArt(slide: slide),
            ),
          ),
          const Spacer(flex: 2),
          Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * 24),
              child: Column(
                children: [
                  Text(
                    slide.caption.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: AppTypography.labelMedium.copyWith(
                      color: slide.accent,
                      letterSpacing: 1.0,
                    ),
                  ),
                  AppSpacing.vGapMd,
                  Text(slide.title,
                      textAlign: TextAlign.center,
                      style: AppTypography.headlineLarge),
                  AppSpacing.vGapMd,
                  Text(
                    slide.subtitle,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium
                        .copyWith(color: vs.textSecondary, height: 1.55),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(flex: 3),
        ],
      ),
    );
  }
}

/// Layered medallion: gradient disc + concentric rings + a floating accent chip
/// and the slide glyph elevated on a card with a colored glow.
class _HeroArt extends StatelessWidget {
  const _HeroArt({required this.slide});

  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    final accent = slide.accent;
    return SizedBox(
      height: 264,
      width: 264,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft gradient disc.
          Container(
            height: 240,
            width: 240,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  accent.withValues(alpha: 0.16),
                  accent.withValues(alpha: 0.04),
                ],
              ),
            ),
          ),
          // Concentric rings.
          _ring(196, accent.withValues(alpha: 0.16)),
          _ring(150, accent.withValues(alpha: 0.12)),
          // Elevated glyph.
          Container(
            height: 116,
            width: 116,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: AppRadius.brXxl,
              boxShadow: AppShadows.glow(accent),
            ),
            child: Icon(slide.icon, size: 54, color: accent),
          ),
          // Floating "verified" caption chip, top-right.
          Positioned(
            top: 6,
            right: 0,
            child: _FloatingChip(
              icon: Icons.bolt_rounded,
              accent: accent,
              tint: slide.accentTint,
            ),
          ),
          // Small decorative dot, bottom-left.
          Positioned(
            bottom: 24,
            left: 10,
            child: Container(
              height: 14,
              width: 14,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
            ),
          ),
          // Tiny ring accent, bottom-right.
          Positioned(
            bottom: 40,
            right: 18,
            child: Container(
              height: 22,
              width: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: accent.withValues(alpha: 0.30), width: 3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ring(double size, Color color) => Container(
        height: size,
        width: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1.5),
        ),
      );
}

class _FloatingChip extends StatelessWidget {
  const _FloatingChip(
      {required this.icon, required this.accent, required this.tint});

  final IconData icon;
  final Color accent;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        shape: BoxShape.circle,
        boxShadow: AppShadows.sm,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xs),
        decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: accent),
      ),
    );
  }
}

/// Full-width gradient CTA with a soft accent glow and a press "squish".
class _GradientCta extends StatelessWidget {
  const _GradientCta({
    required this.label,
    required this.gradient,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final Gradient gradient;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return VSTapScale(
      scale: 0.97,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 54,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: AppRadius.brMd,
          boxShadow: AppShadows.glow(accent),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label,
                style:
                    AppTypography.labelLarge.copyWith(color: AppColors.white)),
            AppSpacing.hGapSm,
            const Icon(Icons.arrow_forward_rounded,
                size: 20, color: AppColors.white),
          ],
        ),
      ),
    );
  }
}
