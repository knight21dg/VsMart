import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/constants/asset_constants.dart';
import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../../shared/providers/settings_provider.dart';
import '../providers/auth_provider.dart';

/// Phone-number login. Collects a mobile number and requests an OTP, then
/// routes to the verification screen. Wired to [authControllerProvider].
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    context.hideKeyboard();
    if (!_formKey.currentState!.validate()) return;

    ref.read(analyticsServiceProvider).loginStarted();
    final ok = await ref
        .read(authControllerProvider.notifier)
        .sendOtp(_phoneController.text.trim());

    if (!mounted) return;
    if (ok) {
      ref.read(analyticsServiceProvider).otpSent();
      await context.pushNamed(RouteNames.otp);
    } else {
      final failure = ref.read(authControllerProvider).failure;
      context.showSnack(
        failure?.message ?? 'Could not send OTP. Please try again.',
        isError: true,
      );
    }
  }

  /// Skip sign-in and explore the app as a guest. Login is requested later, at
  /// checkout or any personal screen.
  Future<void> _continueAsGuest() async {
    await ref.read(guestModeProvider.notifier).enable();
    if (!mounted) return;
    context.goNamed(RouteNames.home);
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final isLoading = ref.watch(
      authControllerProvider.select((s) => s.isLoading),
    );
    final sessionExpired = ref.watch(sessionExpiredProvider);

    return Scaffold(
      body: Stack(
        children: [
          // Soft brand wash behind the header for depth.
          const _TopBrandWash(),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xxl,
                AppSpacing.xl,
                AppSpacing.xxl,
                AppSpacing.xl,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.lg),
                    const Center(child: _BrandMark()),
                    const SizedBox(height: AppSpacing.xl),
                    if (sessionExpired) ...[
                      _SessionExpiredBanner(
                        onDismiss: () => ref
                            .read(sessionExpiredProvider.notifier)
                            .state = false,
                      ),
                      AppSpacing.vGapLg,
                    ],
                    Text(
                      'Welcome back',
                      textAlign: TextAlign.center,
                      style: AppTypography.displayMedium,
                    ),
                    AppSpacing.vGapSm,
                    Text(
                      'Log in to shop daily groceries and manage\nyour VS Credit account.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium.copyWith(
                        color: vs.textSecondary,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.giant),
                    VSPhoneField(
                      controller: _phoneController,
                      label: 'Mobile Number',
                      hint: 'Enter mobile number',
                      validator: Validators.phone,
                      autofocus: false,
                      onSubmitted: (_) => _sendOtp(),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const _SecureNote(),
                    const SizedBox(height: AppSpacing.xl),
                    VSButton(
                      label: 'Send OTP',
                      isLoading: isLoading,
                      onPressed: _sendOtp,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextButton.icon(
                      onPressed: _continueAsGuest,
                      icon: Icon(Icons.storefront_outlined,
                          size: 18, color: vs.textSecondary),
                      label: Text(
                        'Skip for now — browse as guest',
                        style: AppTypography.labelLarge
                            .copyWith(color: vs.textSecondary),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const _TrustStrip(),
                    const SizedBox(height: AppSpacing.xxl),
                    const _CreateAccountLink(),
                    AppSpacing.vGapLg,
                    const _LegalFooter(),
                    AppSpacing.vGapSm,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A faint green-to-transparent wash at the top of the screen — adds depth
/// without competing with the form.
class _TopBrandWash extends StatelessWidget {
  const _TopBrandWash();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        height: 320,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.vsGreen.withValues(alpha: 0.10),
              AppColors.vsGreen.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }
}

/// The VS Märt logo presented on a clean white badge with a soft glow, so it
/// reads on both light and dark themes.
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 156,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft halo behind the badge.
          Container(
            width: 188,
            height: 188,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Color(0x2216A34A), Color(0x0016A34A)],
              ),
            ),
          ),
          Container(
            width: 132,
            height: 132,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: AppRadius.brXl,
              boxShadow: AppShadows.md,
            ),
            child: Image.asset(
              AssetConstants.logo,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const _LogoFallback(),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoFallback extends StatelessWidget {
  const _LogoFallback();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.eco_rounded, color: AppColors.vsGreen, size: 30),
        const SizedBox(height: 2),
        Text(
          'VS MÄRT',
          style: AppTypography.labelLarge.copyWith(
            color: AppColors.vsGreen,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

/// Notice shown when the user was signed out because their session expired
/// (a 401/refresh failure forced a logout), so the bounce isn't unexplained.
class _SessionExpiredBanner extends StatelessWidget {
  const _SessionExpiredBanner({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: vs.offerTint,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: vs.offer.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 20, color: vs.offer),
          AppSpacing.hGapMd,
          Expanded(
            child: Text(
              'Your session expired. Please sign in again.',
              style: AppTypography.bodySmall.copyWith(color: vs.textSecondary),
            ),
          ),
          InkResponse(
            onTap: onDismiss,
            radius: AppSpacing.lg,
            child: Icon(Icons.close_rounded, size: 18, color: vs.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Reassurance line under the phone field.
class _SecureNote extends StatelessWidget {
  const _SecureNote();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.verified_user_rounded, size: 14, color: vs.textSecondary),
        const SizedBox(width: AppSpacing.xs),
        Text(
          "We'll text a 6-digit code to verify your number.",
          style: AppTypography.bodySmall.copyWith(color: vs.textSecondary),
        ),
      ],
    );
  }
}

/// Three trust signals in a soft surface card: secure login, fresh groceries,
/// and the credit facility.
class _TrustStrip extends StatelessWidget {
  const _TrustStrip();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.lg,
        horizontal: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
        boxShadow: AppShadows.xs,
      ),
      child: const Row(
        children: [
          Expanded(
            child: _TrustItem(
              icon: Icons.lock_rounded,
              color: AppColors.vsGreen,
              label: 'Secure\nLogin',
            ),
          ),
          _TrustDivider(),
          Expanded(
            child: _TrustItem(
              icon: Icons.local_grocery_store_rounded,
              color: AppColors.trustBlue,
              label: 'Fresh\nGroceries',
            ),
          ),
          _TrustDivider(),
          Expanded(
            child: _TrustItem(
              icon: Icons.credit_card_rounded,
              color: AppColors.offerOrange,
              label: 'VS\nCredit',
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustDivider extends StatelessWidget {
  const _TrustDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 36, color: context.vsColors.border);
  }
}

class _TrustItem extends StatelessWidget {
  const _TrustItem({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Column(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 19, color: color),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          label,
          textAlign: TextAlign.center,
          style: AppTypography.labelSmall.copyWith(
            color: vs.textSecondary,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

class _CreateAccountLink extends StatelessWidget {
  const _CreateAccountLink();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'New to VS Märt? ',
          style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
        ),
        GestureDetector(
          onTap: () => context.pushNamed(RouteNames.register),
          child: Text(
            'Create account',
            style: AppTypography.labelLarge.copyWith(
              color: AppColors.vsGreen,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _LegalFooter extends StatelessWidget {
  const _LegalFooter();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final style = AppTypography.bodySmall.copyWith(color: vs.textSecondary);
    final emphasis = style.copyWith(
      color: context.colors.onSurface,
      fontWeight: FontWeight.w600,
    );
    return Column(
      children: [
        Text(
          'By continuing you agree to our',
          textAlign: TextAlign.center,
          style: style,
        ),
        AppSpacing.vGapXs,
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () => context.pushNamed(RouteNames.terms),
              child: Text('Terms of Service', style: emphasis),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Text('•', style: style),
            ),
            GestureDetector(
              onTap: () => context.pushNamed(RouteNames.privacyPolicy),
              child: Text('Privacy Policy', style: emphasis),
            ),
          ],
        ),
      ],
    );
  }
}
