import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/constants/app_constants.dart';
import '../../../../app/constants/asset_constants.dart';
import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../providers/auth_provider.dart';

/// OTP verification — a full-page experience with a vector illustration in a
/// soft brand halo, a 6-digit segmented code field, animated inline error
/// feedback, and a resend countdown. Wired to [authControllerProvider].
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  String _code = '';
  bool _hasError = false;
  String? _errorText;
  int _secondsLeft = AppConstants.otpResendSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = AppConstants.otpResendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  String _formatPhone(String? phone) {
    if (phone == null || phone.length != AppConstants.phoneNumberLength) {
      return AppConstants.defaultCountryCode;
    }
    return '${AppConstants.defaultCountryCode} ${phone.substring(0, 5)} ${phone.substring(5)}';
  }

  Future<void> _verify() async {
    context.hideKeyboard();
    if (_code.length != AppConstants.otpLength) {
      setState(() {
        _hasError = true;
        _errorText = 'Enter all ${AppConstants.otpLength} digits of the code.';
      });
      return;
    }
    final ok = await ref.read(authControllerProvider.notifier).verifyOtp(_code);
    if (!mounted) return;
    if (ok) {
      ref.read(analyticsServiceProvider).otpVerified();
      final isNewUser = ref.read(authControllerProvider).isNewUser;
      if (isNewUser) {
        context.goNamed(RouteNames.register);
      } else {
        context.goNamed(RouteNames.home);
      }
    } else {
      // The verify path is fully guarded, so [failure.message] is always a
      // clean, human-readable string (never a raw typecast). We still provide a
      // friendly fallback for the common "wrong code" case.
      final failure = ref.read(authControllerProvider).failure;
      final message = failure?.message ??
          'That code isn\'t right. Please check the '
              '${AppConstants.otpLength} digits and try again.';
      setState(() {
        _hasError = true;
        _errorText = message;
      });
      context.showSnack(message, isError: true);
    }
  }

  Future<void> _resend() async {
    final phone = ref.read(authControllerProvider).phone;
    if (phone == null) return;
    final ok = await ref.read(authControllerProvider.notifier).sendOtp(phone);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _hasError = false;
        _errorText = null;
      });
      _startCountdown();
      context.showSnack('A new code has been sent.');
    } else {
      final failure = ref.read(authControllerProvider).failure;
      context.showSnack(
        failure?.message ?? 'Could not resend the code. Please try again.',
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final state = ref.watch(authControllerProvider);

    return Scaffold(
      body: Stack(
        children: [
          // Soft brand wash behind the illustration for depth.
          const _TopBrandWash(),
          SafeArea(
            child: Column(
              children: [
                // Lightweight top bar with a circular back button.
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
                  child: Row(
                    children: [
                      _CircleBackButton(onTap: () => context.pop()),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxl,
                      vertical: AppSpacing.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: AppSpacing.sm),
                        const _OtpIllustration(),
                        const SizedBox(height: AppSpacing.xl),
                        Text(
                          'Verify your number',
                          textAlign: TextAlign.center,
                          style: AppTypography.headlineLarge,
                        ),
                        AppSpacing.vGapSm,
                        Text.rich(
                          TextSpan(
                            text:
                                'Enter the ${AppConstants.otpLength}-digit code we sent to\n',
                            style: AppTypography.bodyMedium.copyWith(
                                color: vs.textSecondary, height: 1.5),
                            children: [
                              TextSpan(
                                text: _formatPhone(state.phone),
                                style: AppTypography.labelLarge.copyWith(
                                    color: context.colors.onSurface),
                              ),
                            ],
                          ),
                          textAlign: TextAlign.center,
                        ),
                        AppSpacing.vGapSm,
                        GestureDetector(
                          onTap: () => context.pop(),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.xs),
                            child: Text(
                              'Change number',
                              style: AppTypography.labelMedium.copyWith(
                                color: vs.brand,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                        VSOTPField(
                          hasError: _hasError,
                          onChanged: (v) => setState(() {
                            _code = v;
                            _hasError = false;
                            _errorText = null;
                          }),
                          onCompleted: (_) => _verify(),
                        ),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: _errorText == null
                              ? const SizedBox(height: AppSpacing.xl)
                              : Padding(
                                  key: const ValueKey('otp-error'),
                                  padding: const EdgeInsets.only(
                                      top: AppSpacing.md,
                                      bottom: AppSpacing.md),
                                  child: _ErrorChip(text: _errorText!),
                                ),
                        ),
                        _ResendRow(
                          secondsLeft: _secondsLeft,
                          onResend: _resend,
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xxl,
                    AppSpacing.sm,
                    AppSpacing.xxl,
                    AppSpacing.md,
                  ),
                  child: VSButton(
                    label: 'Verify & Continue',
                    isLoading: state.isLoading,
                    trailingIcon: Icons.arrow_forward_rounded,
                    onPressed: _verify,
                  ),
                ),
                const _PrivacyNote(),
                AppSpacing.vGapMd,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Faint green-to-transparent wash at the top of the screen, behind the hero.
class _TopBrandWash extends StatelessWidget {
  const _TopBrandWash();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        height: 360,
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

/// The verification vector inside a soft circular brand halo.
class _OtpIllustration extends StatelessWidget {
  const _OtpIllustration();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return SizedBox(
      height: 196,
      width: 196,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: vs.brandTint,
              boxShadow: [
                BoxShadow(
                  color: AppColors.vsGreen.withValues(alpha: 0.16),
                  blurRadius: 36,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: SvgPicture.asset(
              AssetConstants.otpVerification,
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }
}

/// Circular, theme-aware back button used in the top bar.
class _CircleBackButton extends StatelessWidget {
  const _CircleBackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Material(
      color: context.colors.surface,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          height: 42,
          width: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: vs.border),
          ),
          child: Icon(Icons.arrow_back_rounded,
              size: 20, color: context.colors.onSurface),
        ),
      ),
    );
  }
}

/// Inline error pill shown beneath the code field.
class _ErrorChip extends StatelessWidget {
  const _ErrorChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: vs.danger.withValues(alpha: 0.08),
        borderRadius: AppRadius.brMd,
        border: Border.all(color: vs.danger.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: vs.danger),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(color: vs.danger),
            ),
          ),
        ],
      ),
    );
  }
}

/// Resend countdown / call-to-action shown beneath the code field.
class _ResendRow extends StatelessWidget {
  const _ResendRow({required this.secondsLeft, required this.onResend});

  final int secondsLeft;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    if (secondsLeft > 0) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.schedule_rounded, size: 16, color: vs.textSecondary),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'Resend code in 00:${secondsLeft.toString().padLeft(2, '0')}',
            style: AppTypography.labelMedium.copyWith(color: vs.textSecondary),
          ),
        ],
      );
    }
    return Column(
      children: [
        Text(
          "Didn't receive the code?",
          style: AppTypography.bodySmall.copyWith(color: vs.textSecondary),
        ),
        AppSpacing.vGapXs,
        GestureDetector(
          onTap: onResend,
          child: Text(
            'Resend OTP',
            style: AppTypography.labelLarge.copyWith(
              color: AppColors.trustBlue,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// Tiny reassurance line above the bottom safe area.
class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.lock_outline_rounded, size: 13, color: vs.textSecondary),
        const SizedBox(width: AppSpacing.xs),
        Text(
          'Your code is private and never shared.',
          style: AppTypography.bodySmall.copyWith(color: vs.textSecondary),
        ),
      ],
    );
  }
}
