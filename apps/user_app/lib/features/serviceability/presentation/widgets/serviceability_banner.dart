import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../address/presentation/providers/address_selection_provider.dart';
import '../../../location/presentation/providers/location_providers.dart';
import '../../../location/presentation/widgets/location_search_sheet.dart';
import '../providers/serviceability_gate_providers.dart';
import '../providers/serviceability_providers.dart';

/// A slim status strip reflecting the customer's serviceability for their current
/// location:
///  • serviceable   → green chip with the zone ETA
///  • not serviceable → amber "we're not here yet" strip, TAP to change location
///    (the app no longer hard-locks out-of-area users — browsing is free, ordering
///    is gated at checkout, so this is where the customer is told + can fix it)
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
    final l10n = context.l10n;
    if (result.serviceable) {
      // Serviceable but the store can't take orders right now → amber info strip
      // (the catalog stays visible; checkout is hard-blocked server-side).
      if (result.storeOpen == false) {
        return _Strip(
          color: vs.offerTint,
          iconColor: vs.offer,
          icon: Icons.access_time_rounded,
          child: Text(
            result.opensAt != null
                ? l10n.serviceStoreClosedResumesAt(result.opensAt!)
                : l10n.serviceStoreClosed,
            style: AppTypography.labelMedium
                .copyWith(color: vs.offer, fontWeight: FontWeight.w600),
          ),
        );
      }
      if (result.capacityReached == true) {
        return _Strip(
          color: vs.offerTint,
          iconColor: vs.offer,
          icon: Icons.local_shipping_outlined,
          child: Text(
            l10n.serviceSlotsFull,
            style: AppTypography.labelMedium
                .copyWith(color: vs.offer, fontWeight: FontWeight.w600),
          ),
        );
      }
      final eta = result.estimatedDeliveryMinutes;
      final zone = result.zoneName;
      final label =
          eta != null ? l10n.serviceDeliveringIn(eta) : (zone ?? '');
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
              if (eta != null && zone != null && zone.isNotEmpty)
                TextSpan(
                  text: '  ·  $zone',
                  style: TextStyle(color: vs.textSecondary),
                ),
            ],
          ),
        ),
      );
    }

    // Resolved but outside coverage → "we're not here yet", tap to change the
    // delivery location (opens the place-search sheet, then re-checks).
    return _Strip(
      color: vs.offerTint,
      iconColor: vs.offer,
      icon: Icons.location_off_rounded,
      onTap: () => _changeLocation(context, ref),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.codeOutsideServiceAreaTitle,
              style: AppTypography.labelMedium
                  .copyWith(color: vs.offer, fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            l10n.commonChange,
            style: AppTypography.labelMedium.copyWith(
              color: vs.offer,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changeLocation(BuildContext context, WidgetRef ref) async {
    final picked = await showLocationSearchSheet(context);
    if (picked == null) return;
    // Persist the pick as the active (manual) location FIRST, so catalog +
    // serviceability re-bind to the NEW spot and the green verdict sticks instead
    // of reverting to the old saved address on the next rebuild.
    ref.read(locationControllerProvider.notifier).applyPickedLocation(picked);
    await ref.read(serviceabilityGateProvider.notifier).recheckCoordinate(
          latitude: picked.latitude,
          longitude: picked.longitude,
          pincode: picked.pincode,
        );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({
    required this.color,
    required this.iconColor,
    required this.icon,
    required this.child,
    this.onTap,
  });

  final Color color;
  final Color iconColor;
  final IconData icon;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
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
    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
  }
}
