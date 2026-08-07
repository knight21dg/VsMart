import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes/route_paths.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/extensions/num_extensions.dart';
import 'collection_confirm_screen.dart';

/// Home banner shown while a cash collection is waiting to be confirmed.
///
/// [CollectionConfirmScreen] and its endpoint were fully built and tested, but
/// **nothing ever navigated to them** — so an agent could arrive at the door and
/// the customer had no way to reach the OTP they were being asked for. The
/// collection simply couldn't complete.
///
/// This is time-critical (someone is standing there), so it belongs on Home
/// rather than buried in the credit section. Collapses to nothing when there is
/// no pending collection, so it can be dropped into any scroll view.
class PendingCollectionBanner extends ConsumerWidget {
  const PendingCollectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(collectionConfirmProvider).valueOrNull;
    if (pending == null) return const SizedBox.shrink();

    final vs = context.vsColors;
    return Padding(
      padding: AppSpacing.screenHorizontal,
      child: InkWell(
        onTap: () => context.pushNamed(RouteNames.collectionConfirm),
        borderRadius: AppRadius.brLg,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: vs.brandTint,
            borderRadius: AppRadius.brLg,
            border: Border.all(color: vs.brand.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                height: 38,
                width: 38,
                decoration:
                    BoxDecoration(color: vs.brand, shape: BoxShape.circle),
                child: const Icon(Icons.payments_rounded,
                    color: AppColors.white, size: 20),
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${pending.agentName} is collecting '
                      '${pending.amount.asCurrency}',
                      style: AppTypography.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Tap to show your confirmation code',
                      style: AppTypography.bodySmall
                          .copyWith(color: vs.textSecondary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: vs.brand),
            ],
          ),
        ),
      ),
    );
  }
}
