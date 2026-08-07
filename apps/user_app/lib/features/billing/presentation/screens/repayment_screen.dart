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
import '../../../../core/l10n/status_labels.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/billing_enums.dart';
import '../providers/billing_providers.dart';

/// Repayment flow (Phase 4H) — choose an amount (or a preset share of the
/// outstanding balance) and a method. UPI/Card/Bank settle the ledger
/// immediately; Cash Collection raises an agent pickup request (Phase 4I).
class RepaymentScreen extends ConsumerStatefulWidget {
  const RepaymentScreen({super.key});

  @override
  ConsumerState<RepaymentScreen> createState() => _RepaymentScreenState();
}

class _RepaymentScreenState extends ConsumerState<RepaymentScreen> {
  final _amount = TextEditingController();
  int _percent = 100;
  RepaymentMethod _method = RepaymentMethod.upi;
  bool _seeded = false;
  num _outstanding = 0;

  /// Stable idempotency key for this repayment attempt, reused across retries so
  /// a timed-out request that reached the server isn't charged/recorded twice.
  String? _idempotencyKey;

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
    // Reuse the same key across retries of this attempt; mint one per attempt.
    _idempotencyKey ??= 'repay_${DateTime.now().microsecondsSinceEpoch}';
    if (_method == RepaymentMethod.cashCollection) {
      final record = await ref
          .read(collectionControllerProvider.notifier)
          .request(amount: _payable, idempotencyKey: _idempotencyKey);
      if (!mounted) return;
      if (record != null) {
        _idempotencyKey = null;
        context.showSnack(context.l10n.billingCollectionRequested);
        context.pop();
      } else {
        context.showSnack(context.l10n.billingCollectionRequestError,
            isError: true);
      }
      return;
    }
    final ok = await ref
        .read(repaymentControllerProvider.notifier)
        .pay(amount: _payable, method: _method, idempotencyKey: _idempotencyKey);
    if (!mounted) return;
    if (ok) {
      _idempotencyKey = null;
      context.pushReplacementNamed(RouteNames.repaymentSuccess);
    } else {
      // Prefer the actionable envelope (KYC_REQUIRED, credit gates…) when the
      // backend returned one; otherwise show the generic retry message.
      final failure = ref.read(lastRepaymentFailureProvider);
      if (failure != null && failure.isActionable) {
        presentFailure(context, ref, failure, onRetry: _proceed);
      } else {
        context.showSnack(context.l10n.billingPaymentFailed, isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final overviewAsync = ref.watch(billingOverviewProvider);
    return Scaffold(
      appBar: VSAppBar(title: context.l10n.billingMakePayment),
      body: overviewAsync.when(
        loading: () => const VSLoadingView(),
        error: (e, _) => VSErrorView(
          failure: e is Failure ? e : null,
          onRetry: () => ref.invalidate(billingOverviewProvider),
        ),
        data: (data) {
          if (!_seeded) {
            _outstanding = data.outstanding;
            _amount.text = '${data.outstanding.round()}';
            _seeded = true;
          }
          return _body(context, data.outstanding, data.minimumDue);
        },
      ),
    );
  }

  Widget _body(BuildContext context, num outstanding, num minimumDue) {
    final vs = context.vsColors;
    final isBusy = ref.watch(repaymentControllerProvider) ||
        ref.watch(collectionControllerProvider);
    final isCollection = _method == RepaymentMethod.cashCollection;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: AppSpacing.screen,
            children: [
              _OutstandingCard(outstanding: outstanding, minimumDue: minimumDue),
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
                    Text(context.l10n.billingEnterAmount,
                        style: AppTypography.titleMedium),
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
              Text(context.l10n.checkoutPaymentMethod,
                  style: AppTypography.headlineSmall),
              AppSpacing.vGapMd,
              for (final method in RepaymentMethod.values) ...[
                _MethodTile(
                  method: method,
                  selected: _method == method,
                  onTap: () => setState(() => _method = method),
                ),
                AppSpacing.vGapSm,
              ],
            ],
          ),
        ),
        _PayBar(
          amount: _payable,
          isLoading: isBusy,
          actionLabel: isCollection
              ? context.l10n.billingRequestCollection
              : context.l10n.billingProceedToPay,
          onProceed: _payable > 0 ? _proceed : null,
        ),
      ],
    );
  }
}

class _OutstandingCard extends StatelessWidget {
  const _OutstandingCard({required this.outstanding, required this.minimumDue});

  final num outstanding;
  final num minimumDue;

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
                Text(context.l10n.billingOutstandingAmount.toUpperCase(),
                    style: AppTypography.labelSmall
                        .copyWith(color: faint, letterSpacing: 0.5)),
                AppSpacing.vGapXs,
                Text(outstanding.asCurrency,
                    style: AppTypography.displayMedium
                        .copyWith(color: AppColors.white)),
              ],
            ),
          ),
          if (minimumDue > 0)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(context.l10n.creditMinimumDue,
                    style: AppTypography.labelSmall.copyWith(color: faint)),
                AppSpacing.vGapXs,
                Text(minimumDue.asCurrency,
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
    required this.method,
    required this.selected,
    required this.onTap,
  });

  final RepaymentMethod method;
  final bool selected;
  final VoidCallback onTap;

  (IconData, String) _meta(BuildContext context) => switch (method) {
        RepaymentMethod.upi =>
          (Icons.account_balance_wallet_rounded, 'GPay, PhonePe, Paytm'),
        RepaymentMethod.card =>
          (Icons.credit_card_rounded, context.l10n.billingDebitCreditCard),
        RepaymentMethod.bankTransfer =>
          (Icons.account_balance_rounded, context.l10n.billingNeftImpsTransfer),
        RepaymentMethod.cashCollection =>
          (Icons.local_atm_rounded, context.l10n.billingRequestAgentPickup),
      };

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final (icon, subtitle) = _meta(context);
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
                  Text(method.labelL10n(context.l10n),
                      style: AppTypography.titleMedium),
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
    required this.actionLabel,
    required this.onProceed,
  });

  final num amount;
  final bool isLoading;
  final String actionLabel;
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
                Text(context.l10n.billingAmount,
                    style: AppTypography.bodyMedium
                        .copyWith(color: vs.textSecondary)),
                Text(amount.asCurrency, style: AppTypography.priceLarge),
              ],
            ),
            AppSpacing.vGapMd,
            VSButton(
              label: actionLabel,
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
                Text(context.l10n.billingSecurePayments,
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
