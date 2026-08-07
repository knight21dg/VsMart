import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../data/places_service.dart';
import '../../domain/entities/place_suggestion.dart';
import '../../domain/entities/resolved_location.dart';
import '../providers/location_providers.dart';
import '../screens/location_picker_screen.dart';

/// Presents the place-search → pin-drop flow as a modal sheet and returns the
/// confirmed [ResolvedLocation] (or null if the user backs out).
///
/// Flow: type an area → Google Places suggestions → tap one → the map pin-picker
/// opens centred there → confirm the exact spot. Used by the serviceability
/// "Change location" sheet and the Add-address screen so location-picking is
/// identical everywhere.
Future<ResolvedLocation?> showLocationSearchSheet(BuildContext context) {
  return showModalBottomSheet<ResolvedLocation>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (_) => const _LocationSearchSheet(),
  );
}

class _LocationSearchSheet extends ConsumerStatefulWidget {
  const _LocationSearchSheet();

  @override
  ConsumerState<_LocationSearchSheet> createState() =>
      _LocationSearchSheetState();
}

class _LocationSearchSheetState extends ConsumerState<_LocationSearchSheet> {
  final _search = TextEditingController();
  final _session = PlacesService.newSessionToken();
  Timer? _debounce;
  List<PlaceSuggestion> _suggestions = [];
  bool _searching = false;
  bool _busy = false;
  bool _searched = false;
  // Set when the search itself couldn't run (no key / proxy error / offline) —
  // distinct from a search that genuinely matched nothing.
  bool _searchFailed = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() {
        _suggestions = [];
        _searched = false;
        _searchFailed = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    setState(() => _searching = true);
    final res = await ref
        .read(placesServiceProvider)
        .autocomplete(q, sessionToken: _session);
    if (!mounted) return;
    setState(() {
      _suggestions = res.suggestions;
      _searchFailed = res.failed;
      _searching = false;
      _searched = true;
    });
  }

  Future<void> _pickSuggestion(PlaceSuggestion s) async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final detail = await ref
        .read(placesServiceProvider)
        .detail(s.placeId, sessionToken: _session);
    if (!mounted) return;
    setState(() => _busy = false);
    if (detail == null) {
      context.showSnack(context.l10n.locationPlaceLoadError, isError: true);
      return;
    }
    final picked = await showLocationPickerSheet(context, initial: detail);
    if (!mounted || picked == null) return;
    Navigator.of(context).pop(picked);
  }

  /// Resolve the device GPS, then open the pin-picker centred there.
  Future<void> _useCurrentLocation() async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final svc = ref.read(locationServiceProvider);
    final granted = await svc.ensurePermission();
    final pos = granted ? await svc.getCurrentPosition() : null;
    if (!mounted) return;
    if (pos == null) {
      setState(() => _busy = false);
      context.showSnack(
        granted
            ? context.l10n.locationCouldNotGet
            : context.l10n.locationPermissionNeeded,
        isError: true,
      );
      return;
    }
    final resolved =
        await ref.read(geocodingServiceProvider).reverse(pos.latitude, pos.longitude);
    if (!mounted) return;
    setState(() => _busy = false);
    final picked = await showLocationPickerSheet(context, initial: resolved);
    if (!mounted || picked == null) return;
    Navigator.of(context).pop(picked);
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final l10n = context.l10n;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg,
          AppSpacing.xl + bottom + safeBottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              decoration: BoxDecoration(
                color: vs.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(l10n.serviceChangeLocation, style: AppTypography.titleLarge),
          AppSpacing.vGapSm,
          Text(
            l10n.locationSearchSubtitle,
            style: AppTypography.bodySmall.copyWith(color: vs.textSecondary),
          ),
          AppSpacing.vGapLg,
          VSTextField(
            controller: _search,
            hint: l10n.locationSearchHint,
            prefixIcon: Icons.search_rounded,
            autofocus: true,
            enabled: !_busy,
            textInputAction: TextInputAction.search,
            onChanged: _onQueryChanged,
          ),
          // Quick "use my GPS" shortcut → opens the pin-picker at the current spot.
          AppSpacing.vGapMd,
          InkWell(
            onTap: _busy ? null : _useCurrentLocation,
            borderRadius: AppRadius.brMd,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                children: [
                  Icon(Icons.my_location_rounded, size: 20, color: vs.brand),
                  AppSpacing.hGapMd,
                  Text(l10n.addressUseCurrentLocation,
                      style: AppTypography.titleMedium.copyWith(color: vs.brand)),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: vs.border),
          if (_searching) ...[
            AppSpacing.vGapLg,
            const Center(
              child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ] else if (_suggestions.isNotEmpty) ...[
            AppSpacing.vGapSm,
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: vs.border),
                itemBuilder: (_, i) {
                  final s = _suggestions[i];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.location_on_outlined, color: vs.brand),
                    title: Text(s.primary,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: s.secondary.isEmpty
                        ? null
                        : Text(s.secondary,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: _busy ? null : () => _pickSuggestion(s),
                  );
                },
              ),
            ),
          ] else if (_searchFailed) ...[
            AppSpacing.vGapLg,
            Row(
              children: [
                Icon(Icons.cloud_off_rounded, size: 18, color: vs.offer),
                AppSpacing.hGapSm,
                Expanded(
                  child: Text(
                    l10n.locationSearchUnavailable,
                    style: AppTypography.bodySmall.copyWith(color: vs.offer),
                  ),
                ),
              ],
            ),
          ] else if (_searched) ...[
            AppSpacing.vGapLg,
            Text(l10n.locationNoMatches,
                style: AppTypography.bodySmall.copyWith(color: vs.textSecondary)),
          ],
          if (_busy) ...[
            AppSpacing.vGapLg,
            const Center(
              child: SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          ],
        ],
      ),
    );
  }
}
