import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';

/// A titled review section with an edit action, completion status, and summary
/// rows. Reused for Personal / Address / Identity / Selfie / Credit on the
/// review screen.
class VSReviewSection extends StatelessWidget {
  const VSReviewSection({
    super.key,
    required this.title,
    required this.icon,
    required this.complete,
    required this.children,
    this.onEdit,
  });

  final String title;
  final IconData icon;
  final bool complete;
  final List<Widget> children;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: vs.brand),
              AppSpacing.hGapSm,
              Expanded(child: Text(title, style: AppTypography.titleMedium)),
              Icon(
                complete
                    ? Icons.check_circle_rounded
                    : Icons.error_outline_rounded,
                size: 18,
                color: complete ? vs.success : vs.warning,
              ),
              if (onEdit != null)
                TextButton(
                  onPressed: onEdit,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  ),
                  child: const Text('Edit'),
                ),
            ],
          ),
          const Divider(height: AppSpacing.lg),
          ...children,
        ],
      ),
    );
  }
}

/// A label/value row inside a [VSReviewSection].
class VSReviewRow extends StatelessWidget {
  const VSReviewRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: AppTypography.bodySmall
                    .copyWith(color: vs.textSecondary)),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: AppTypography.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// A single node in a [VSStatusTimeline].
class VSTimelineStep {
  const VSTimelineStep({
    required this.title,
    required this.subtitle,
    required this.state,
  });

  final String title;
  final String subtitle;
  final VSTimelineState state;
}

enum VSTimelineState { done, current, pending }

/// Vertical progress timeline used on the verification status screen.
class VSStatusTimeline extends StatelessWidget {
  const VSStatusTimeline({super.key, required this.steps});

  final List<VSTimelineStep> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          _Row(step: steps[i], isLast: i == steps.length - 1),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.step, required this.isLast});

  final VSTimelineStep step;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final color = switch (step.state) {
      VSTimelineState.done => vs.success,
      VSTimelineState.current => vs.brand,
      VSTimelineState.pending => vs.textSecondary,
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                height: 24,
                width: 24,
                decoration: BoxDecoration(
                  color: step.state == VSTimelineState.pending
                      ? Colors.transparent
                      : color,
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2),
                ),
                child: step.state == VSTimelineState.done
                    ? const Icon(Icons.check_rounded,
                        size: 14, color: AppColors.white)
                    : step.state == VSTimelineState.current
                        ? const Icon(Icons.circle, size: 8, color: AppColors.white)
                        : null,
              ),
              if (!isLast)
                Expanded(
                  child: Container(width: 2, color: vs.border),
                ),
            ],
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(step.title,
                      style: AppTypography.titleMedium.copyWith(
                        color: step.state == VSTimelineState.pending
                            ? vs.textSecondary
                            : null,
                      )),
                  Text(step.subtitle,
                      style: AppTypography.bodySmall
                          .copyWith(color: vs.textSecondary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
