import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../domain/credit_access.dart';

/// The single "you don't have VS Credit yet — apply now" surface, reused
/// everywhere a credit balance would otherwise show (Account, Checkout). Renders
/// apply / under-review / re-apply states off [access]. Never shows any figures.
class CreditApplyCard extends StatelessWidget {
  const CreditApplyCard({super.key, required this.access, this.dense = false});

  final CreditAccess access;

  /// Tighter padding + smaller hero for inline use (e.g. inside checkout).
  final bool dense;

  ({IconData icon, String title, String body, String cta, String route})
      _content(BuildContext context) => switch (access) {
            // These route to the CREDIT application, not the KYC document hub.
            // Sending "Apply for VS Credit" to /kyc was why the apply flow
            // appeared to go nowhere — the hub is an identity checklist and
            // never collected or submitted a credit request.
            CreditAccess.pending => (
                icon: Icons.hourglass_top_rounded,
                title: context.l10n.creditAppUnderReview,
                body:
                    "We're reviewing your application. Your VS Credit line "
                        'unlocks here once approved.',
                cta: 'View Status',
                route: RouteNames.creditApplicationStatus,
              ),
            CreditAccess.rejected => (
                icon: Icons.error_outline_rounded,
                title: context.l10n.creditAppNotApproved,
                body: "Your last credit application wasn't approved. Review your "
                    'details and apply again.',
                cta: 'Re-apply',
                route: RouteNames.creditApplicationStatus,
              ),
            _ => (
                icon: Icons.lock_open_rounded,
                title: "You don't have VS Credit yet",
                body: 'Shop now, pay later. Verify your identity once, then '
                    'apply for a limit that suits you.',
                cta: 'Apply for VS Credit',
                route: RouteNames.creditApplicationStatus,
              ),
          };

  @override
  Widget build(BuildContext context) {
    final c = _content(context);
    final faint = AppColors.white.withValues(alpha: 0.9);
    final pad = dense ? AppSpacing.lg : AppSpacing.xl;
    final heroSize = dense ? 52.0 : 64.0;
    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        gradient: AppColors.creditGradient,
        borderRadius: AppRadius.brXl,
        boxShadow: AppShadows.glow(AppColors.trustBlue),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: heroSize,
                width: heroSize,
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(c.icon,
                    color: AppColors.white, size: dense ? 26 : 32),
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.title,
                        style: (dense
                                ? AppTypography.titleLarge
                                : AppTypography.headlineSmall)
                            .copyWith(color: AppColors.white)),
                    const SizedBox(height: 2),
                    Text(c.body,
                        style: AppTypography.bodySmall.copyWith(
                            color: faint, height: 1.45)),
                  ],
                ),
              ),
            ],
          ),
          AppSpacing.vGapLg,
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => context.pushNamed(c.route),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.white,
                foregroundColor: AppColors.trustBlue,
                elevation: 0,
                minimumSize: const Size.fromHeight(48),
                shape:
                    const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(c.cta,
                      style: AppTypography.labelLarge
                          .copyWith(color: AppColors.trustBlue)),
                  const SizedBox(width: AppSpacing.sm),
                  const Icon(Icons.arrow_forward_rounded,
                      size: 18, color: AppColors.trustBlue),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
