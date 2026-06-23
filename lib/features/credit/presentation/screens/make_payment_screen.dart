import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/app_error_presenter.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/credit_account.dart';
import '../providers/credit_providers.dart';

/// Make a credit repayment: choose an amount (or a preset share of the
/// outstanding balance) and a payment method. Backed by [creditAccountProvider]
/// and [creditPaymentControllerProvider].
class MakePaymentScreen extends ConsumerStatefulWidget {
  const MakePaymentScreen({super.key});

  @override
  ConsumerState<MakePaymentScreen> createState() => _MakePaymentScreenState();
}

class _MakePaymentScreenState extends ConsumerState<MakePaymentScreen> {
  final _amount = TextEditingController();
  int _percent = 100;
  int _method = 0;
  bool _seeded = false;
  num _outstanding = 0;

  static const _methods = [
    (Icons.account_balance_rounded, 'UPI', 'GPay, PhonePe, Paytm'),
    (Icons.qr_code_2_rounded, 'QR Code', 'Scan & Pay instantly'),
    (Icons.link_rounded, 'Payment Link', 'Send via SMS/WhatsApp'),
    (Icons.local_atm_rounded, 'Cash Collection', 'Request agent pickup'),
  ];

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _applyPercent(int percent) {
    setState(() {
      _percent = percent;
      _amount.text = '${(_outstanding * percent / 100).round()}';
    });
  }

  num get _payable => num.tryParse(_amount.text) ?? 0;

  Future<void> _proceed() async {
    final label = _methods[_method].$2;
    // Cash collection is an at-home agent pickup, not an online repayment.
    if (label == 'Cash Collection') {
      unawaited(context.pushNamed(RouteNames.cashCollectionRequest));
      return;
    }
    final ok = await ref.read(creditPaymentControllerProvider.notifier).pay(
          amount: _payable,
          method: label,
        );
    if (!mounted) return;
    if (ok) {
      context.pushReplacementNamed(RouteNames.paymentSuccess);
    } else {
      // Prefer the actionable envelope (KYC_REQUIRED, credit gates…) when the
      // backend returned one; otherwise show the generic retry message.
      final failure = ref.read(lastPaymentFailureProvider);
      if (failure != null && failure.isActionable) {
        presentFailure(context, ref, failure, onRetry: _proceed);
      } else {
        context.showSnack('Payment failed. Please try again.', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountAsync = ref.watch(creditAccountProvider);
    return Scaffold(
      appBar: const VSAppBar(title: 'Make Payment'),
      body: accountAsync.when(
        loading: () => const VSLoadingView(),
        error: (e, _) => VSErrorView(
          failure: e is Failure ? e : null,
          onRetry: () => ref.invalidate(creditAccountProvider),
        ),
        data: (account) {
          if (!_seeded) {
            _outstanding = account.outstanding;
            _amount.text = '${account.outstanding.round()}';
            _seeded = true;
          }
          return _body(context, account);
        },
      ),
    );
  }

  Widget _body(BuildContext context, CreditAccount account) {
    final vs = context.vsColors;
    final isPaying = ref.watch(creditPaymentControllerProvider);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: AppSpacing.screen,
            children: [
              _OutstandingCard(amount: account.outstanding, dueDate: '31 July'),
              AppSpacing.vGapLg,
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: AppRadius.brLg,
                  border: Border.all(color: vs.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Enter Amount', style: AppTypography.titleMedium),
                    AppSpacing.vGapSm,
                    TextField(
                      controller: _amount,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: AppTypography.headlineMedium,
                      onChanged: (_) => setState(() => _percent = 0),
                      decoration: const InputDecoration(
                        prefixText: '₹ ',
                        prefixStyle: TextStyle(fontSize: 20),
                      ),
                    ),
                    AppSpacing.vGapMd,
                    Row(
                      children: [
                        for (final p in [25, 50, 75, 100]) ...[
                          _PercentChip(
                            percent: p,
                            selected: _percent == p,
                            onTap: () => _applyPercent(p),
                          ),
                          if (p != 100) AppSpacing.hGapSm,
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              AppSpacing.vGapLg,
              Text('Payment Method', style: AppTypography.headlineSmall),
              AppSpacing.vGapMd,
              for (var i = 0; i < _methods.length; i++) ...[
                _MethodTile(
                  icon: _methods[i].$1,
                  title: _methods[i].$2,
                  subtitle: _methods[i].$3,
                  selected: _method == i,
                  onTap: () => setState(() => _method = i),
                ),
                AppSpacing.vGapSm,
              ],
            ],
          ),
        ),
        _PayBar(
          amount: _payable,
          isLoading: isPaying,
          onProceed: _payable > 0 ? _proceed : null,
        ),
      ],
    );
  }
}

class _OutstandingCard extends StatelessWidget {
  const _OutstandingCard({required this.amount, required this.dueDate});

  final num amount;
  final String dueDate;

  @override
  Widget build(BuildContext context) {
    final faint = AppColors.white.withValues(alpha: 0.85);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: AppColors.creditGradient,
        borderRadius: AppRadius.brXl,
        boxShadow: AppShadows.glow(AppColors.trustBlue),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('OUTSTANDING AMOUNT',
                    style: AppTypography.labelSmall
                        .copyWith(color: faint, letterSpacing: 0.5)),
                AppSpacing.vGapXs,
                Text(amount.asCurrency,
                    style: AppTypography.displayMedium
                        .copyWith(color: AppColors.white)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Due Date',
                  style: AppTypography.labelSmall.copyWith(color: faint)),
              AppSpacing.vGapXs,
              Text(dueDate,
                  style: AppTypography.titleLarge
                      .copyWith(color: AppColors.white)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PercentChip extends StatelessWidget {
  const _PercentChip({
    required this.percent,
    required this.selected,
    required this.onTap,
  });

  final int percent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.brPill,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? vs.trust : context.colors.surface,
            borderRadius: AppRadius.brPill,
            border: Border.all(color: selected ? vs.trust : vs.border),
          ),
          child: Text('$percent%',
              style: AppTypography.labelMedium.copyWith(
                color: selected ? AppColors.white : null,
              )),
        ),
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brLg,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? vs.trustTint : context.colors.surface,
          borderRadius: AppRadius.brLg,
          border: Border.all(color: selected ? vs.trust : vs.border),
        ),
        child: Row(
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: context.colors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: vs.border),
              ),
              child: Icon(icon, color: vs.trust, size: 22),
            ),
            AppSpacing.hGapMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.titleMedium),
                  Text(subtitle,
                      style: AppTypography.bodySmall
                          .copyWith(color: vs.textSecondary)),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? vs.trust : vs.border,
            ),
          ],
        ),
      ),
    );
  }
}

class _PayBar extends StatelessWidget {
  const _PayBar({
    required this.amount,
    required this.isLoading,
    required this.onProceed,
  });

  final num amount;
  final bool isLoading;
  final VoidCallback? onProceed;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: vs.border)),
      ),
      child: SafeArea(
        minimum: AppSpacing.screen,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Amount to Pay',
                    style: AppTypography.bodyMedium
                        .copyWith(color: vs.textSecondary)),
                Text(amount.asCurrency, style: AppTypography.priceLarge),
              ],
            ),
            AppSpacing.vGapMd,
            VSButton(
              label: 'Proceed to Payment',
              trailingIcon: Icons.arrow_forward_rounded,
              isLoading: isLoading,
              onPressed: onProceed,
            ),
            AppSpacing.vGapSm,
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.shield_outlined, size: 14, color: vs.success),
                AppSpacing.hGapSm,
                Text('100% Secure Payments',
                    style: AppTypography.bodySmall
                        .copyWith(color: vs.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
