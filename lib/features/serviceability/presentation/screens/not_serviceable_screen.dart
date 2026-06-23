import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../providers/serviceability_gate_providers.dart';

/// Full-screen serviceability HARD LOCK (Zepto/Blinkit style).
///
/// When the customer's device location resolves OUTSIDE every serving zone (or
/// coverage can't be confirmed) the router funnels the entire app here, with a
/// single action: **Change location**. While the GPS check is still resolving it
/// renders a brief "Checking your area…" loader instead of locking content.
///
/// Unlocking is automatic: changing the location re-runs the serviceability
/// check via [ServiceabilityGateController]; once it resolves serviceable the
/// router's `refreshListenable` flips the redirect and lands the user on Home.
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
                Text('Checking your area…',
                    style: AppTypography.titleMedium),
                AppSpacing.vGapXs,
                Text(
                  'Confirming we deliver where you are.',
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
                    ? 'Set your location to continue'
                    : "VS Mart isn't in your area yet",
                textAlign: TextAlign.center,
                style: AppTypography.headlineMedium,
              ),
              AppSpacing.vGapSm,
              Text(
                couldntLocate
                    ? "We couldn't confirm your location. Set it so we can "
                        'check if VS Mart delivers near you.'
                    : "We're expanding fast. Change your location to shop from a "
                        'serviceable area near you.',
                textAlign: TextAlign.center,
                style:
                    AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xxl),
              VSButton(
                label: 'Change location',
                icon: Icons.edit_location_alt_rounded,
                onPressed: () => _openChangeLocationSheet(context),
              ),
            ],
          ),
        ),
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
  final _pincode = TextEditingController();
  bool _busy = false;
  String? _note;

  @override
  void dispose() {
    _pincode.dispose();
    super.dispose();
  }

  Future<void> _useMyLocation() async {
    setState(() {
      _busy = true;
      _note = null;
    });
    final status =
        await ref.read(serviceabilityGateProvider.notifier).recheck();
    _handleResult(status, detected: true);
  }

  Future<void> _checkPincode() async {
    final pin = _pincode.text.trim();
    if (pin.length != 6) {
      setState(() => _note = 'Enter a valid 6-digit pincode');
      return;
    }
    setState(() {
      _busy = true;
      _note = null;
    });
    final status = await ref
        .read(serviceabilityGateProvider.notifier)
        .recheckCoordinate(pincode: pin);
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
          ? "Couldn't get your location. Check GPS/permissions and try again, "
              'or enter a pincode.'
          : "We don't deliver there yet. Try a different location.";
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
          Text('Change location', style: AppTypography.titleLarge),
          AppSpacing.vGapSm,
          Text(
            'Use your current location or enter a pincode to check coverage.',
            style: AppTypography.bodySmall.copyWith(color: vs.textSecondary),
          ),
          AppSpacing.vGapLg,
          VSButton(
            label: 'Use my current location',
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
                child: Text('OR',
                    style: AppTypography.labelSmall
                        .copyWith(color: vs.textSecondary)),
              ),
              Expanded(child: Divider(color: vs.border)),
            ],
          ),
          AppSpacing.vGapMd,
          VSTextField(
            controller: _pincode,
            label: 'Pincode',
            hint: '6-digit pincode',
            keyboardType: TextInputType.number,
            enabled: !_busy,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            onSubmitted: (_) => _busy ? null : _checkPincode(),
          ),
          AppSpacing.vGapMd,
          VSButton(
            label: 'Check this pincode',
            variant: VSButtonVariant.secondary,
            isLoading: _busy,
            onPressed: _busy ? null : _checkPincode,
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
        ],
      ),
    );
  }
}
