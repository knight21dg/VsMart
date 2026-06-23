import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../providers/verification_providers.dart';

/// Confirmation after submitting the verification application: the application
/// id, timeline, and next actions.
class ApplicationSubmittedScreen extends ConsumerWidget {
  const ApplicationSubmittedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    final app = ref.watch(submittedApplicationProvider);
    final submitted = app?.submittedAt;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: AppSpacing.screen,
                children: [
                  const SizedBox(height: AppSpacing.xl),
                  Center(
                    child: Container(
                      height: 88,
                      width: 88,
                      decoration: const BoxDecoration(
                        color: AppColors.vsGreen,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: AppColors.white, size: 48),
                    ),
                  ),
                  AppSpacing.vGapLg,
                  Text('Application Submitted!',
                      textAlign: TextAlign.center,
                      style: AppTypography.headlineLarge),
                  AppSpacing.vGapSm,
                  Text(
                    'Our team is reviewing your details. Your credit limit will '
                    'reflect in your profile once approved.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium
                        .copyWith(color: vs.textSecondary),
                  ),
                  AppSpacing.vGapXl,
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: context.colors.surface,
                      borderRadius: AppRadius.brLg,
                      border: Border.all(color: vs.border),
                    ),
                    child: Column(
                      children: [
                        _Row(
                            label: 'Application ID',
                            value: app?.applicationId ?? '—'),
                        const Divider(height: AppSpacing.xl),
                        _Row(
                          label: 'Submitted On',
                          value: submitted == null
                              ? '—'
                              : DateFormat('d MMM yyyy, h:mm a')
                                  .format(submitted),
                        ),
                        const Divider(height: AppSpacing.xl),
                        _Row(
                          label: 'Expected Review',
                          value: 'Within ${app?.expectedReviewDays ?? 2} days',
                        ),
                        const Divider(height: AppSpacing.xl),
                        _Row(
                          label: 'Current Status',
                          value: 'Pending',
                          valueColor: vs.warning,
                        ),
                      ],
                    ),
                  ),
                  AppSpacing.vGapLg,
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: vs.trustTint,
                      borderRadius: AppRadius.brMd,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 18, color: vs.trust),
                        AppSpacing.hGapSm,
                        Expanded(
                          child: Text(
                            'Credit reflection may take up to 2–4 hours after approval.',
                            style: AppTypography.bodySmall
                                .copyWith(color: vs.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: AppSpacing.screen,
              child: Column(
                children: [
                  VSButton(
                    label: 'Track Application',
                    trailingIcon: Icons.arrow_forward_rounded,
                    onPressed: () =>
                        context.pushReplacementNamed(RouteNames.verificationStatus),
                  ),
                  AppSpacing.vGapSm,
                  Row(
                    children: [
                      Expanded(
                        child: VSOutlinedButton(
                          label: 'Go to Home',
                          onPressed: () => context.goNamed(RouteNames.home),
                        ),
                      ),
                      AppSpacing.hGapMd,
                      Expanded(
                        child: VSOutlinedButton(
                          label: 'Contact Support',
                          onPressed: () => context.pushNamed(RouteNames.support),
                        ),
                      ),
                    ],
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

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary)),
        Text(value,
            style: AppTypography.labelLarge
                .copyWith(color: valueColor ?? context.colors.onSurface)),
      ],
    );
  }
}
