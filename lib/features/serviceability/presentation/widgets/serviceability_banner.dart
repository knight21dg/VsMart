import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../address/presentation/providers/address_selection_provider.dart';
import '../providers/serviceability_providers.dart';

/// A slim status strip reflecting the customer's serviceability for their
/// selected delivery address:
///  • serviceable   → green chip with the zone ETA
///  • not serviceable → amber info strip (the app-wide hard lock already blocks
///    out-of-coverage users, so this is informational only — no navigation)
///  • not resolved   → nothing (don't nag before a location is chosen)
class ServiceabilityBanner extends ConsumerWidget {
  const ServiceabilityBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final address = ref.watch(selectedAddressProvider);
    if (address == null) return const SizedBox.shrink();

    final async = ref.watch(serviceabilityProvider);
    final result = async.valueOrNull;
    // While the first check is in flight with nothing cached, stay quiet.
    if (result == null) return const SizedBox.shrink();

    final vs = context.vsColors;
    if (result.serviceable) {
      final eta = result.estimatedDeliveryMinutes;
      final label = eta != null
          ? 'Delivery in $eta min'
          : 'Delivering to your area';
      final zone = result.zoneName;
      return _Strip(
        color: vs.successTint,
        iconColor: vs.success,
        icon: Icons.bolt_rounded,
        child: Text.rich(
          TextSpan(
            style: AppTypography.labelMedium.copyWith(color: vs.success),
            children: [
              TextSpan(
                text: label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (zone != null && zone.isNotEmpty)
                TextSpan(
                  text: '  ·  $zone',
                  style: TextStyle(color: vs.textSecondary),
                ),
            ],
          ),
        ),
      );
    }

    // Resolved but outside coverage — informational only (the app-wide hard
    // lock already prevents an out-of-coverage user from reaching this screen).
    return _Strip(
      color: vs.offerTint,
      iconColor: vs.offer,
      icon: Icons.location_off_rounded,
      child: Text(
        'Not available at this address yet',
        style: AppTypography.labelMedium
            .copyWith(color: vs.offer, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({
    required this.color,
    required this.iconColor,
    required this.icon,
    required this.child,
  });

  final Color color;
  final Color iconColor;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      color: color,
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: child),
        ],
      ),
    );
  }
}
