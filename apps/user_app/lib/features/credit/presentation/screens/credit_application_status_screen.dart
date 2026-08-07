import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/errors/failures.dart';
import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/credit_application.dart';
import '../providers/credit_application_provider.dart';

/// Where a customer lands after applying, and the screen the Credit tab sends
/// them to while a decision is pending. Shows the real server-side state — not
/// a local guess — so "under review" survives an app restart.
class CreditApplicationStatusScreen extends ConsumerWidget {
  const CreditApplicationStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(creditApplicationProvider);
    return Scaffold(
      appBar: VSAppBar(title: context.l10n.verifyCreditApp),
      body: SafeArea(
        child: async.when(
          loading: () => const VSLoadingView(),
          // Coded failures route themselves (auth -> login) rather than
          // stranding the customer on a generic error.
          error: (e, __) => VSErrorView(
            failure: e is Failure ? e : null,
            message: e is Failure ? null : context.l10n.commonSomethingWentWrong,
            onRetry: () => ref.invalidate(creditApplicationProvider),
          ),
          data: (app) => RefreshIndicator(
            onRefresh: () async => ref.invalidate(creditApplicationProvider),
            child: ListView(
              padding: AppSpacing.screen,
              children: [
                AppSpacing.vGapLg,
                _StatusHero(application: app),
                AppSpacing.vGapLg,
                if (app != null) _Details(application: app),
                AppSpacing.vGapXl,
                ..._actions(context, ref, app),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _actions(
      BuildContext context, WidgetRef ref, CreditApplication? app) {
    // Never applied, or free to apply again.
    if (app == null || app.status.canApply) {
      return [
        VSButton(
          label: app == null
              ? context.l10n.billingApplyForCredit
              : context.l10n.verifyReapply,
          trailingIcon: Icons.arrow_forward_rounded,
          onPressed: () => context.pushNamed(RouteNames.creditApplication),
        ),
      ];
    }
    if (app.status == CreditApplicationStatus.approved) {
      return [
        VSButton(
          label: context.l10n.billingCreditTab,
          trailingIcon: Icons.arrow_forward_rounded,
          onPressed: () => context.goNamed(RouteNames.creditDashboard),
        ),
      ];
    }
    // In flight — let them cancel rather than leaving them stuck.
    return [
      VSOutlinedButton(
        label: context.l10n.commonCancel,
        onPressed: () async {
          await ref.read(creditApplicationControllerProvider).withdraw();
          if (context.mounted) {
            context.showSnack('Your credit application was cancelled.');
          }
        },
      ),
    ];
  }
}

class _StatusHero extends StatelessWidget {
  const _StatusHero({required this.application});

  final CreditApplication? application;

  @override
  Widget build(BuildContext context) {
    final status = application?.status;
    final (IconData icon, String title, String body) = switch (status) {
      CreditApplicationStatus.submitted ||
      CreditApplicationStatus.underReview =>
        (
          Icons.hourglass_top_rounded,
          context.l10n.creditAppUnderReview,
          "We're reviewing your application. You'll get a notification as soon "
              'as there is a decision — usually within a day.',
        ),
      CreditApplicationStatus.approved => (
          Icons.check_circle_outline_rounded,
          'VS Credit approved',
          'Your credit limit is '
              '${application?.approvedLimit?.asCurrency ?? ''}. '
              'You can pay with VS Credit at checkout right away.',
        ),
      CreditApplicationStatus.rejected => (
          Icons.error_outline_rounded,
          context.l10n.creditAppNotApproved,
          application?.rejectionReason.isNotEmpty == true
              ? application!.rejectionReason
              : "Your application wasn't approved this time.",
        ),
      CreditApplicationStatus.withdrawn => (
          Icons.undo_rounded,
          'Application cancelled',
          'You cancelled your credit application. You can apply again anytime.',
        ),
      _ => (
          Icons.credit_card_rounded,
          context.l10n.billingUnlockCredit,
          'Shop now, pay later. Apply once and we\'ll set your limit.',
        ),
    };

    final faint = AppColors.white.withValues(alpha: 0.9);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: const BoxDecoration(
        gradient: AppColors.creditGradient,
        borderRadius: AppRadius.brXl,
      ),
      child: Column(
        children: [
          Container(
            height: 72,
            width: 72,
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.white, size: 36),
          ),
          AppSpacing.vGapLg,
          Text(title,
              textAlign: TextAlign.center,
              style: AppTypography.headlineSmall
                  .copyWith(color: AppColors.white)),
          AppSpacing.vGapSm,
          Text(body,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(color: faint)),
        ],
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.application});

  final CreditApplication application;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final rows = <(String, String)>[
      (context.l10n.verifyOccupation, application.occupation),
      (
        context.l10n.verifyMonthlyIncome,
        application.monthlyIncome?.asCurrency ?? '—'
      ),
      (
        context.l10n.verifyRequestedLimit,
        application.requestedLimit?.asCurrency ?? '—'
      ),
      if (application.approvedLimit != null)
        ('Approved limit', application.approvedLimit!.asCurrency),
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
      ),
      child: Column(
        children: [
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label,
                      style: AppTypography.bodyMedium
                          .copyWith(color: vs.textSecondary)),
                  Text(value, style: AppTypography.labelLarge),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
