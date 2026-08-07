import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/app_error_presenter.dart';
import '../../../../core/errors/error_handler.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../auth/presentation/providers/session_provider.dart';
import '../../../location/presentation/providers/location_providers.dart';
import '../../../location/presentation/widgets/location_search_sheet.dart';
import '../providers/serviceability_gate_providers.dart';
import '../providers/serviceability_providers.dart';

/// Full-screen out-of-area lead-capture screen (Zepto/Blinkit style).
///
/// Only a customer whose GPS location resolves POSITIVELY OUTSIDE every serving
/// zone ([GateStatus.unserviceable]) is funnelled here by the router — it is not a
/// blanket hard lock: a serviceable or merely-couldn't-confirm
/// ([GateStatus.locationUnavailable]) verdict keeps browsing soft on Home. The
/// screen offers two real actions: **Change location** (re-check a new spot) and
/// **Notify me when you're here** (register expansion interest). While the GPS
/// check is still resolving it renders a brief "Checking your area…" loader.
///
/// Unlocking is automatic: changing the location persists the pick and re-runs the
/// serviceability check via [ServiceabilityGateController]; once it resolves
/// serviceable the router's `refreshListenable` flips the redirect and lands the
/// user on Home — now bound to the newly-picked location.
class NotServiceableScreen extends ConsumerStatefulWidget {
  const NotServiceableScreen({super.key, this.latitude, this.longitude, this.pincode});

  final double? latitude;
  final double? longitude;
  final String? pincode;

  @override
  ConsumerState<NotServiceableScreen> createState() =>
      _NotServiceableScreenState();
}

class _NotServiceableScreenState extends ConsumerState<NotServiceableScreen> {
  @override
  void initState() {
    super.initState();
    // If we landed here before any check ran (first launch lands on the lock
    // screen while `unresolved`), kick the once-per-session GPS resolve.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(serviceabilityGateProvider.notifier).ensureChecked();
    });
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final gate = ref.watch(serviceabilityGateProvider);

    // ----- Resolving: brief, non-locking loading state. -----
    if (gate.isResolving) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                AppSpacing.vGapLg,
                Text(context.l10n.serviceCheckingArea,
                    style: AppTypography.titleMedium),
                AppSpacing.vGapXs,
                Text(
                  context.l10n.serviceConfirmingDelivery,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium
                      .copyWith(color: vs.textSecondary),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // `locationUnavailable` means GPS was denied / coverage couldn't be
    // confirmed — frame the copy as "set your location" rather than a definitive
    // "we're not here yet".
    final couldntLocate = gate == GateStatus.locationUnavailable;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  height: 96,
                  width: 96,
                  decoration: BoxDecoration(
                    color: vs.offerTint,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.location_off_rounded,
                      size: 44, color: vs.offer),
                ),
              ),
              AppSpacing.vGapXl,
              Text(
                couldntLocate
                    ? context.l10n.serviceSetLocationTitle
                    : context.l10n.serviceNotInAreaTitle,
                textAlign: TextAlign.center,
                style: AppTypography.headlineMedium,
              ),
              AppSpacing.vGapSm,
              Text(
                couldntLocate
                    ? context.l10n.serviceCouldntConfirmBody
                    : context.l10n.serviceExpandingBody,
                textAlign: TextAlign.center,
                style:
                    AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xxl),
              VSButton(
                label: context.l10n.serviceChangeLocation,
                icon: Icons.edit_location_alt_rounded,
                onPressed: () => _openChangeLocationSheet(context),
              ),
              // Genuinely out of coverage → let the customer register interest so
              // we can tell them when VS Mart reaches their area. Skipped in the
              // "couldn't locate" case, where the fix is setting a location, not
              // waiting for expansion.
              if (!couldntLocate) ...[
                AppSpacing.vGapMd,
                VSButton(
                  label: context.l10n.serviceNotifyWhenHere,
                  icon: Icons.notifications_active_outlined,
                  variant: VSButtonVariant.secondary,
                  onPressed: () => _openNotifySheet(context),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _openNotifySheet(BuildContext context) {
    final resolved = ref.read(resolvedLocationProvider);
    final pincode = (widget.pincode?.isNotEmpty ?? false)
        ? widget.pincode
        : (resolved?.pincode.isNotEmpty ?? false)
            ? resolved!.pincode
            : null;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) => _NotifyMeSheet(
        latitude: widget.latitude ?? resolved?.latitude,
        longitude: widget.longitude ?? resolved?.longitude,
        pincode: pincode,
      ),
    );
  }

  void _openChangeLocationSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) => const _ChangeLocationSheet(),
    );
  }
}

/// Bottom sheet that lets a locked user re-detect their GPS location or type a
/// pincode, then re-runs the serviceability check. On a serviceable result the
/// router auto-unlocks; otherwise it surfaces a "still not covered" note.
class _ChangeLocationSheet extends ConsumerStatefulWidget {
  const _ChangeLocationSheet();

  @override
  ConsumerState<_ChangeLocationSheet> createState() =>
      _ChangeLocationSheetState();
}

class _ChangeLocationSheetState extends ConsumerState<_ChangeLocationSheet> {
  bool _busy = false;
  String? _note;
  // When GPS/permission is the blocker, we surface a direct route to the right
  // system settings screen instead of a dead-end "try again".
  VoidCallback? _settingsAction;
  String? _settingsLabel;

  Future<void> _useMyLocation() async {
    setState(() {
      _busy = true;
      _note = null;
      _settingsAction = null;
      _settingsLabel = null;
    });
    // Diagnose WHY a fix might be unavailable before firing the check, so we can
    // point the user at the exact fix (system location toggle vs app permission).
    final svc = ref.read(locationServiceProvider);
    final perm = await svc.checkPermission();
    if (!mounted) return;
    if (perm == LocationPermissionState.serviceOff) {
      setState(() {
        _busy = false;
        _note = context.l10n.serviceLocationOffNote;
        _settingsLabel = context.l10n.serviceOpenLocationSettings;
        _settingsAction = svc.openLocationSettings;
      });
      return;
    }
    if (perm == LocationPermissionState.deniedForever) {
      setState(() {
        _busy = false;
        _note = context.l10n.serviceLocationBlockedNote;
        _settingsLabel = context.l10n.serviceOpenAppSettings;
        _settingsAction = svc.openAppSettings;
      });
      return;
    }
    final status =
        await ref.read(serviceabilityGateProvider.notifier).recheck();
    _handleResult(status, detected: true);
  }

  /// Search a place → drop the pin → re-check serviceability for that point.
  Future<void> _searchAndPick() async {
    final picked = await showLocationSearchSheet(context);
    if (picked == null || !mounted) return;
    setState(() {
      _busy = true;
      _note = null;
    });
    // Persist the pick as the active (manual) location so once the gate unlocks
    // and the router lands the user on Home, catalog + serviceability bind to the
    // NEW spot instead of reverting to the old address / GPS location.
    ref.read(locationControllerProvider.notifier).applyPickedLocation(picked);
    final status =
        await ref.read(serviceabilityGateProvider.notifier).recheckCoordinate(
              latitude: picked.latitude,
              longitude: picked.longitude,
              pincode: picked.pincode,
            );
    _handleResult(status, detected: false);
  }

  void _handleResult(GateStatus status, {required bool detected}) {
    if (!mounted) return;
    if (status == GateStatus.serviceable) {
      // The router's refreshListenable will redirect off the lock screen to
      // Home; just close the sheet.
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _note = status == GateStatus.locationUnavailable && detected
          ? context.l10n.serviceNoGpsFixNote
          : context.l10n.serviceDontDeliverThereNote;
    });
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg + bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.l10n.serviceChangeLocation,
              style: AppTypography.titleLarge),
          AppSpacing.vGapSm,
          Text(
            context.l10n.serviceChangeLocationBody,
            style: AppTypography.bodySmall.copyWith(color: vs.textSecondary),
          ),
          AppSpacing.vGapLg,
          VSButton(
            label: context.l10n.serviceUseMyCurrentLocation,
            icon: Icons.my_location_rounded,
            isLoading: _busy,
            onPressed: _busy ? null : _useMyLocation,
          ),
          AppSpacing.vGapMd,
          Row(
            children: [
              Expanded(child: Divider(color: vs.border)),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Text(context.l10n.commonOr,
                    style: AppTypography.labelSmall
                        .copyWith(color: vs.textSecondary)),
              ),
              Expanded(child: Divider(color: vs.border)),
            ],
          ),
          AppSpacing.vGapMd,
          VSButton(
            label: context.l10n.serviceSearchAreaDropPin,
            icon: Icons.search_rounded,
            variant: VSButtonVariant.secondary,
            onPressed: _busy ? null : _searchAndPick,
          ),
          if (_note != null) ...[
            AppSpacing.vGapMd,
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: vs.offerTint,
                borderRadius: AppRadius.brMd,
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: vs.offer),
                  AppSpacing.hGapSm,
                  Expanded(
                    child: Text(_note!,
                        style: AppTypography.bodySmall
                            .copyWith(color: vs.offer)),
                  ),
                ],
              ),
            ),
          ],
          if (_settingsAction != null) ...[
            AppSpacing.vGapMd,
            VSButton(
              label: _settingsLabel ?? context.l10n.serviceOpenSettings,
              icon: Icons.settings_rounded,
              variant: VSButtonVariant.secondary,
              onPressed: _busy ? null : _settingsAction,
            ),
          ],
        ],
      ),
    );
  }
}

/// Lead-capture sheet for out-of-area customers: submits their phone (+ optional
/// name) and best-known coordinates to the expansion-request endpoint so VS Mart
/// can notify them when it starts serving their area.
class _NotifyMeSheet extends ConsumerStatefulWidget {
  const _NotifyMeSheet({this.latitude, this.longitude, this.pincode});

  final double? latitude;
  final double? longitude;
  final String? pincode;

  @override
  ConsumerState<_NotifyMeSheet> createState() => _NotifyMeSheetState();
}

class _NotifyMeSheetState extends ConsumerState<_NotifyMeSheet> {
  late final TextEditingController _phoneController;
  late final TextEditingController _nameController;
  bool _busy = false;
  bool _done = false;
  String? _fieldError;

  @override
  void initState() {
    super.initState();
    final user = ref.read(sessionControllerProvider).user;
    _phoneController = TextEditingController(text: user?.phone ?? '');
    _nameController = TextEditingController(text: user?.name ?? '');
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final mobile = _phoneController.text.trim();
    final name = _nameController.text.trim();
    if (mobile.length < 10) {
      setState(() => _fieldError = context.l10n.serviceEnterValidPhone);
      return;
    }
    setState(() {
      _busy = true;
      _fieldError = null;
    });
    try {
      await ref.read(serviceabilityDataSourceProvider).requestExpansion(
            name: name,
            mobile: mobile,
            pincode: widget.pincode ?? '',
            latitude: widget.latitude,
            longitude: widget.longitude,
          );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _done = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      presentFailure(context, ref, ErrorHandler.handle(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg + bottom,
      ),
      child: _done
          ? _buildSuccess(context, vs)
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(context.l10n.serviceNotifyWhenHere,
                    style: AppTypography.titleLarge),
                AppSpacing.vGapSm,
                Text(
                  context.l10n.serviceNotifyBody,
                  style:
                      AppTypography.bodySmall.copyWith(color: vs.textSecondary),
                ),
                AppSpacing.vGapLg,
                TextField(
                  controller: _nameController,
                  enabled: !_busy,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: context.l10n.serviceNameOptional,
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                  ),
                ),
                AppSpacing.vGapMd,
                TextField(
                  controller: _phoneController,
                  enabled: !_busy,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
                  ],
                  decoration: InputDecoration(
                    labelText: context.l10n.addressPhone,
                    hintText: context.l10n.servicePhoneHintExample,
                    errorText: _fieldError,
                    prefixIcon: const Icon(Icons.phone_outlined),
                  ),
                ),
                AppSpacing.vGapLg,
                VSButton(
                  label: context.l10n.serviceNotifyMe,
                  icon: Icons.notifications_active_outlined,
                  isLoading: _busy,
                  onPressed: _busy ? null : _submit,
                ),
              ],
            ),
    );
  }

  Widget _buildSuccess(BuildContext context, VSColors vs) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            height: 72,
            width: 72,
            decoration: BoxDecoration(
              color: vs.successTint,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_rounded, size: 36, color: vs.success),
          ),
        ),
        AppSpacing.vGapLg,
        Text(context.l10n.serviceWellNotifyYou,
            textAlign: TextAlign.center, style: AppTypography.titleLarge),
        AppSpacing.vGapSm,
        Text(
          context.l10n.serviceNotifySuccessBody,
          textAlign: TextAlign.center,
          style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
        ),
        AppSpacing.vGapLg,
        VSButton(
          label: context.l10n.commonDone,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
