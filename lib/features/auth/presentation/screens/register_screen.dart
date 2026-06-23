import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/constants/app_constants.dart';
import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
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
      context.showSnack(
        failure?.message ?? 'Registration failed. Please try again.',
        isError: true,
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
                      Text('Almost there!', style: AppTypography.headlineLarge),
                      AppSpacing.vGapSm,
                      Text(
                        'Tell us your name to finish setting up your account. '
                        'No email or paperwork needed.',
                        style: AppTypography.bodyMedium
                            .copyWith(color: vs.textSecondary, height: 1.5),
                      ),
                      AppSpacing.vGapLg,
                      _VerifiedPhoneChip(phone: _formatPhone(state.phone)),
                      AppSpacing.vGapLg,
                      VSTextField(
                        controller: _name,
                        label: 'Full Name',
                        hint: 'e.g. Jane Doe',
                        prefixIcon: Icons.person_outline_rounded,
                        textInputAction: TextInputAction.next,
                        validator: (v) =>
                            Validators.required(v, field: 'Full name'),
                      ),
                      AppSpacing.vGapLg,
                      Row(
                        children: [
                          Text('Referral Code',
                              style: AppTypography.labelMedium),
                          const Spacer(),
                          Text('Optional',
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
                    label: 'Create Account',
                    trailingIcon: Icons.arrow_forward_rounded,
                    isLoading: state.isLoading,
                    onPressed: _submit,
                  ),
                  AppSpacing.vGapSm,
                  TextButton(
                    onPressed: state.isLoading ? null : _useDifferentNumber,
                    child: Text('Use a different number',
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
                Text('Verified number',
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
                Text('Want shop-now-pay-later?',
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
