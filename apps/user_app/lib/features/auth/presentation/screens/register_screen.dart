import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/constants/app_constants.dart';
import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/app_error_presenter.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../providers/auth_provider.dart';

/// Lightweight account setup for a freshly verified phone number. KYC is no
/// longer required up front, so we only ask for the customer's name and an
/// optional referral code — VS Credit / KYC is offered later, from the success
/// screen and the Credit tab.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _referral = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _referral.dispose();
    super.dispose();
  }

  String _formatPhone(String? phone) {
    if (phone == null || phone.length != AppConstants.phoneNumberLength) {
      return phone ?? '';
    }
    return '${AppConstants.defaultCountryCode} ${phone.substring(0, 5)} ${phone.substring(5)}';
  }

  Future<void> _submit() async {
    context.hideKeyboard();
    if (!_formKey.currentState!.validate()) return;
    final referral = _referral.text.trim();
    final ok = await ref.read(authControllerProvider.notifier).register(
          name: _name.text.trim(),
          referralCode: referral.isEmpty ? null : referral,
        );
    if (!mounted) return;
    if (ok) {
      ref.read(analyticsServiceProvider).registrationCompleted();
      context.goNamed(RouteNames.registrationSuccess);
    } else {
      final failure = ref.read(authControllerProvider).failure;
      presentFailure(
        context,
        ref,
        failure ?? const UnknownFailure('Registration failed. Please try again.'),
        onRetry: _submit,
      );
    }
  }

  Future<void> _useDifferentNumber() async {
    await ref.read(authControllerProvider.notifier).logout();
    if (!mounted) return;
    context.goNamed(RouteNames.login);
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final state = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Text('VS Mart',
            style: AppTypography.headlineSmall.copyWith(color: vs.brand)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: AppSpacing.screen,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppSpacing.vGapSm,
                      const Center(child: _WelcomeMedallion()),
                      AppSpacing.vGapLg,
                      Center(
                        child: Text(context.l10n.authAlmostThere,
                            style: AppTypography.headlineLarge),
                      ),
                      AppSpacing.vGapSm,
                      Center(
                        child: Text(
                          'Tell us your name to finish setting up your account. '
                          'No email or paperwork needed.',
                          textAlign: TextAlign.center,
                          style: AppTypography.bodyMedium
                              .copyWith(color: vs.textSecondary, height: 1.5),
                        ),
                      ),
                      AppSpacing.vGapXl,
                      _VerifiedPhoneChip(phone: _formatPhone(state.phone)),
                      AppSpacing.vGapLg,
                      VSTextField(
                        controller: _name,
                        label: context.l10n.addressFullName,
                        hint: 'e.g. Jane Doe',
                        prefixIcon: Icons.person_outline_rounded,
                        textInputAction: TextInputAction.next,
                        validator: (v) =>
                            Validators.required(v, field: 'Full name'),
                      ),
                      AppSpacing.vGapLg,
                      Row(
                        children: [
                          Text(context.l10n.authReferralCode,
                              style: AppTypography.labelMedium),
                          const Spacer(),
                          Text(context.l10n.commonOptional,
                              style: AppTypography.bodySmall
                                  .copyWith(color: vs.textSecondary)),
                        ],
                      ),
                      AppSpacing.vGapSm,
                      VSTextField(
                        controller: _referral,
                        hint: 'e.g. FRIEND20',
                        prefixIcon: Icons.card_giftcard_outlined,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                      ),
                      AppSpacing.vGapXl,
                      const _CreditLaterNote(),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: AppSpacing.screen,
              child: Column(
                children: [
                  VSButton(
                    label: context.l10n.authCreateAccount,
                    trailingIcon: Icons.arrow_forward_rounded,
                    isLoading: state.isLoading,
                    onPressed: _submit,
                  ),
                  AppSpacing.vGapSm,
                  TextButton(
                    onPressed: state.isLoading ? null : _useDifferentNumber,
                    child: Text(context.l10n.authUseDifferentNumber,
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

/// Layered brand medallion that warms up the top of the sign-up form — soft
/// concentric rings behind a gradient disc holding a "new member" glyph.
class _WelcomeMedallion extends StatelessWidget {
  const _WelcomeMedallion();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    Widget ring(double size, double alpha) => Container(
          height: size,
          width: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: vs.brand.withValues(alpha: alpha),
          ),
        );
    return SizedBox(
      height: 108,
      width: 108,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ring(108, 0.06),
          ring(84, 0.10),
          Container(
            height: 64,
            width: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                vs.brand.withValues(alpha: 0.22),
                vs.brand.withValues(alpha: 0.12),
              ]),
            ),
            child: Icon(Icons.person_add_alt_1_rounded,
                size: 30, color: vs.brand),
          ),
        ],
      ),
    );
  }
}

/// Read-only chip confirming the phone number that was just verified.
class _VerifiedPhoneChip extends StatelessWidget {
  const _VerifiedPhoneChip({required this.phone});

  final String phone;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: vs.brandTint,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: vs.brand.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_rounded, size: 20, color: vs.brand),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.authVerifiedNumber,
                    style: AppTypography.labelSmall
                        .copyWith(color: vs.textSecondary)),
                Text(phone.isEmpty ? 'Your mobile number' : phone,
                    style: AppTypography.titleMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Reassures the user that credit / KYC is optional and comes later.
class _CreditLaterNote extends StatelessWidget {
  const _CreditLaterNote();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
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
          Icon(Icons.account_balance_wallet_outlined, size: 22, color: vs.trust),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.l10n.authWantCredit,
                    style: AppTypography.titleMedium),
                const SizedBox(height: 2),
                Text(
                  'Set up VS Credit anytime after signing up — a quick KYC '
                  'unlocks your buy-now-pay-later limit.',
                  style: AppTypography.bodySmall
                      .copyWith(color: vs.textSecondary, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
