import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../domain/entities/resolved_location.dart';
import '../providers/location_providers.dart';
import '../widgets/clean_map_style.dart';

/// Present the pin-picker as a rounded modal bottom sheet (~92% height) so the whole
/// change-location flow stays in sheets instead of pushing a full page.
Future<ResolvedLocation?> showLocationPickerSheet(
  BuildContext context, {
  required ResolvedLocation initial,
  String? title,
}) {
  return showModalBottomSheet<ResolvedLocation>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    // The sheet must NOT be draggable: its drag-to-dismiss competes with panning
    // the map underneath. Close via the picker's own back button instead.
    enableDrag: false,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
      child: ClipRRect(
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        child: LocationPickerScreen(initial: initial, title: title),
      ),
    ),
  );
}

/// Full-screen "drop the pin" picker (Zepto/Swiggy style): the map pans under a
/// fixed centre marker, and the address under the marker is reverse-geocoded on
/// every idle. Returns the confirmed [ResolvedLocation] via `Navigator.pop`.
///
/// Open it with the place the user searched for (or their current location) as
/// [initial]; they fine-tune the exact spot and confirm. Usually presented via
/// [showLocationPickerSheet].
class LocationPickerScreen extends ConsumerStatefulWidget {
  const LocationPickerScreen({
    super.key,
    required this.initial,
    this.title,
  });

  final ResolvedLocation initial;
  final String? title;

  @override
  ConsumerState<LocationPickerScreen> createState() =>
      _LocationPickerScreenState();
}

class _LocationPickerScreenState extends ConsumerState<LocationPickerScreen> {
  GoogleMapController? _map;
  late LatLng _center =
      LatLng(widget.initial.latitude, widget.initial.longitude);
  late ResolvedLocation _resolved = widget.initial;
  bool _geocoding = false;
  bool _locating = false;
  int _idleToken = 0;

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  /// Reverse-geocode the current map centre after movement settles. Guarded by a
  /// token so a stale in-flight lookup never overwrites a newer one.
  Future<void> _onIdle() async {
    final token = ++_idleToken;
    setState(() => _geocoding = true);
    final resolved = await ref
        .read(geocodingServiceProvider)
        .reverse(_center.latitude, _center.longitude);
    if (!mounted || token != _idleToken) return;
    setState(() {
      _resolved = resolved;
      _geocoding = false;
    });
  }

  /// Recentre the map (and therefore the pin) on [target]. `onCameraIdle` then
  /// reverse-geocodes the new spot.
  Future<void> _moveTo(LatLng target) async {
    _center = target;
    await _map?.animateCamera(CameraUpdate.newLatLng(target));
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    final svc = ref.read(locationServiceProvider);
    final granted = await svc.ensurePermission();
    final pos = granted ? await svc.getCurrentPosition() : null;
    if (!mounted) {
      return;
    }
    setState(() => _locating = false);
    if (pos == null) {
      context.showSnack(
        granted
            ? context.l10n.locationCouldNotGet
            : context.l10n.locationPermissionNeeded,
      );
      return;
    }
    final target = LatLng(pos.latitude, pos.longitude);
    _center = target;
    await _map?.animateCamera(CameraUpdate.newLatLngZoom(target, 16.5));
  }

  void _confirm() {
    Navigator.of(context).pop(
      _resolved.copyWith(latitude: _center.latitude, longitude: _center.longitude),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? context.l10n.locationPickerTitle)),
      body: Stack(
        alignment: Alignment.center,
        children: [
          GoogleMap(
            style: kCleanMapStyle,
            initialCameraPosition: CameraPosition(target: _center, zoom: 16.5),
            onMapCreated: (c) => _map = c,
            onCameraMove: (pos) => _center = pos.target,
            onCameraIdle: _onIdle,
            // Tap anywhere to drop the pin there — a faster alternative to
            // nudging the map under a fixed centre pin.
            onTap: _moveTo,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: false,
            // The picker is presented inside a modal bottom sheet, which by
            // default WINS the vertical-drag gesture arena and pans the sheet
            // instead of the map — making the pin impossible to move. Claiming
            // the gestures eagerly hands every drag to the map.
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<OneSequenceGestureRecognizer>(
                  () => EagerGestureRecognizer()),
            },
            padding: const EdgeInsets.only(bottom: 220),
          ),

          // Fixed centre pin — the map moves under it, so it always marks the
          // exact point being picked. Raised so the tip sits on the centre.
          IgnorePointer(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 44),
              child: Icon(Icons.location_pin, size: 48, color: vs.brand),
            ),
          ),

          // "Move the map" hint near the pin.
          Positioned(
            top: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: AppRadius.brPill,
                boxShadow: AppShadows.sm,
              ),
              child: Text(context.l10n.locationDragHint,
                  style: AppTypography.labelSmall),
            ),
          ),

          // Recenter on GPS.
          Positioned(
            right: AppSpacing.lg,
            bottom: 236,
            child: FloatingActionButton.small(
              heroTag: 'picker-locate',
              onPressed: _locating ? null : _useCurrentLocation,
              backgroundColor: context.colors.surface,
              foregroundColor: vs.brand,
              child: _locating
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location_rounded),
            ),
          ),

          // Confirm card.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg,
                  AppSpacing.lg, AppSpacing.lg + MediaQuery.paddingOf(context).bottom),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppRadius.lg)),
                boxShadow: AppShadows.md,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.location_on_rounded, size: 20, color: vs.brand),
                      AppSpacing.hGapSm,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _resolved.displayLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.titleMedium,
                            ),
                            if (_resolved.formatted.isNotEmpty)
                              Text(
                                _resolved.formatted,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.bodySmall
                                    .copyWith(color: vs.textSecondary),
                              ),
                          ],
                        ),
                      ),
                      if (_geocoding)
                        const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                    ],
                  ),
                  AppSpacing.vGapLg,
                  VSButton(
                    label: context.l10n.locationConfirm,
                    icon: Icons.check_rounded,
                    onPressed: _geocoding ? null : _confirm,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
