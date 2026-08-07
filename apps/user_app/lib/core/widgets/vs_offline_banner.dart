import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../extensions/context_extensions.dart';

/// Slim banner shown above commerce screens when offline or syncing. Renders
/// nothing when online.
class VSOfflineBanner extends StatelessWidget {
  const VSOfflineBanner({super.key, this.offline = false, this.syncing = false});

  final bool offline;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    if (!offline && !syncing) return const SizedBox.shrink();
    final vs = context.vsColors;
    final (color, bg, icon, message) = offline
        ? (
            vs.warning,
            AppColors.amberTint,
            Icons.cloud_off_rounded,
            "You're offline — showing saved data"
          )
        : (
            vs.trust,
            vs.trustTint,
            Icons.sync_rounded,
            'Connecting…',
          );
    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: color),
          AppSpacing.hGapSm,
          Text(message,
              style: AppTypography.labelMedium.copyWith(color: color)),
        ],
      ),
    );
  }
}
