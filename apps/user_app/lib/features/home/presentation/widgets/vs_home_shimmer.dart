import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/widgets/widgets.dart';

/// Skeleton placeholder for the home screen while the first data loads.
class VSHomeShimmer extends StatelessWidget {
  const VSHomeShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: AppSpacing.screen,
      children: [
        const VSShimmerBox(height: 48, borderRadius: AppRadius.brLg),
        AppSpacing.vGapLg,
        const VSShimmerBox(height: 140, borderRadius: AppRadius.brXl),
        AppSpacing.vGapLg,
        const VSShimmerBox(height: 120, borderRadius: AppRadius.brXl),
        AppSpacing.vGapLg,
        Row(
          children: List.generate(
            4,
            (_) => const Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: VSShimmerBox(height: 64, borderRadius: AppRadius.brLg),
              ),
            ),
          ),
        ),
        AppSpacing.vGapXl,
        const VSShimmerBox(height: 18, width: 160),
        AppSpacing.vGapMd,
        SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 3,
            separatorBuilder: (_, __) => AppSpacing.hGapMd,
            itemBuilder: (_, __) => const VSShimmerBox(
              width: 150,
              height: 180,
              borderRadius: AppRadius.brLg,
            ),
          ),
        ),
      ],
    );
  }
}
