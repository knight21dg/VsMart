import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';

/// Celebratory endpoint shown after a customer's account is created.
///
/// Matches the "Registration Successful" celebration design: a centered
/// brand wordmark, a white badge wrapping a green success check, the
/// headline + supportive copy, an informational note about credit
/// reflection, and the primary / secondary CTAs.
class RegistrationSuccessScreen extends StatelessWidget {
  const RegistrationSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.xxxl,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'VS Mart',
                      textAlign: TextAlign.center,
                      style: AppTypography.displayMedium.copyWith(
                        color: vs.brand,
                      ),
                    ),
                    AppSpacing.vGapXl,

                    // White badge wrapping the green success check.
                    Container(
                      height: 104,
                      width: 104,
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: vs.brand.withValues(alpha: 0.18),
                            blurRadius: 28,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Container(
                        height: 64,
                        width: 64,
                        decoration: const BoxDecoration(
                          gradient: AppColors.greenGradient,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: AppColors.white,
                          size: 36,
                        ),
                      ),
                    ),
                    AppSpacing.vGapXl,

                    Text(
                      'Registration Successful!',
                      textAlign: TextAlign.center,
                      style: AppTypography.headlineLarge.copyWith(
                        color: vs.brand,
                      ),
                    ),
                    AppSpacing.vGapMd,

                    Text(
                      'Your VS Mart account is ready. Start shopping right '
                      'away — and whenever you want shop-now-pay-later, apply '
                      'for VS Credit in a few quick steps.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium.copyWith(
                        color: vs.textSecondary,
                      ),
                    ),
                    AppSpacing.vGapXl,

                    _CreditNote(vs: vs),
                  ],
                ),
              ),
            ),

            // Bottom CTAs.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.sm,
                AppSpacing.xl,
                AppSpacing.xl,
              ),
              child: Column(
                children: [
                  VSButton(
                    label: 'Go to Home Dashboard',
                    trailingIcon: Icons.arrow_forward_rounded,
                    onPressed: () => context.goNamed(RouteNames.home),
                  ),
                  AppSpacing.vGapSm,
                  TextButton(
                    onPressed: () => context.goNamed(RouteNames.kyc),
                    child: Text(
                      'Apply for VS Credit',
                      style: AppTypography.labelLarge.copyWith(
                        color: vs.brand,
                      ),
                    ),
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

/// Subtle informational banner about credit reflection timing.
class _CreditNote extends StatelessWidget {
  const _CreditNote({required this.vs});

  final VSColors vs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: vs.trustTint,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.trust.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 20, color: vs.trust),
          AppSpacing.hGapMd,
          Expanded(
            child: Text(
              'VS Credit is optional. Apply anytime from the Credit tab — '
              'verification takes just a few minutes.',
              style: AppTypography.labelMedium.copyWith(
                color: context.colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
