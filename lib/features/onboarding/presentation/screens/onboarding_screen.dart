import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/settings_provider.dart';

/// First-run onboarding carousel introducing groceries, credit, and the VS
/// score. Marks onboarding complete and routes to login when finished.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _slides = [
    _Slide(
      icon: Icons.local_shipping_rounded,
      caption: 'Fresh Groceries, Delivered Fast!',
      title: 'Fresh Groceries Delivered To Your Doorstep',
      subtitle:
          'Order vegetables, fruits, dairy products, household essentials, and daily groceries with fast delivery.',
    ),
    _Slide(
      icon: Icons.account_balance_wallet_rounded,
      caption: 'Shop Now, Pay Later',
      title: 'Shop With VS Credit, Pay On Your Terms',
      subtitle:
          'Buy what you need today and settle later with flexible weekly or monthly credit — no hidden charges.',
    ),
    _Slide(
      icon: Icons.trending_up_rounded,
      caption: 'Grow Your VS Score',
      title: 'Build Your Credit Score As You Shop',
      subtitle:
          'Every on-time payment strengthens your VS Score and unlocks higher credit limits and better offers.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _page == _slides.length - 1;

  Future<void> _finish() async {
    await ref.read(onboardingSeenProvider.notifier).complete();
    if (!mounted) return;
    context.goNamed(RouteNames.login);
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _SlideView(slide: _slides[i]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    height: 8,
                    width: i == _page ? 22 : 8,
                    decoration: BoxDecoration(
                      color: i == _page ? vs.brand : vs.border,
                      borderRadius: AppRadius.brPill,
                    ),
                  ),
              ],
            ),
            Padding(
              padding: AppSpacing.screen,
              child: Column(
                children: [
                  VSButton(
                    label: _isLast ? 'Get Started' : 'Next',
                    onPressed: _next,
                  ),
                  AppSpacing.vGapSm,
                  TextButton(
                    onPressed: _finish,
                    child: Text('Skip',
                        style: AppTypography.labelMedium
                            .copyWith(color: vs.textSecondary)),
                  ),
                ],
              ),
            ),
          ],
        ),
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
  });

  final IconData icon;
  final String caption;
  final String title;
  final String subtitle;
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});

  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                color: vs.brandTint,
                borderRadius: AppRadius.brXl,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(slide.caption,
                      style: AppTypography.titleMedium
                          .copyWith(color: vs.brand)),
                  AppSpacing.vGapLg,
                  Icon(slide.icon, size: 88, color: vs.brand),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxxl),
          Text(slide.title,
              textAlign: TextAlign.center,
              style: AppTypography.headlineLarge),
          AppSpacing.vGapMd,
          Text(slide.subtitle,
              textAlign: TextAlign.center,
              style:
                  AppTypography.bodyMedium.copyWith(color: vs.textSecondary)),
        ],
      ),
    );
  }
}
