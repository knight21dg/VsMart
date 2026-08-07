import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/app_error_presenter.dart';
import '../../../../core/errors/error_handler.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/string_extensions.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../auth/presentation/providers/current_user_provider.dart';
import '../../../location/data/address_validation_service.dart';
import '../../../location/domain/entities/resolved_location.dart';
import '../../../location/presentation/providers/location_providers.dart';
import '../../../location/presentation/screens/location_picker_screen.dart';
import '../../../location/presentation/widgets/location_search_sheet.dart';
import '../../domain/entities/address.dart';
import '../providers/address_providers.dart';

/// Add or edit a delivery address. Pass [initial] (via go_router `extra`) to
/// edit an existing address.
class AddAddressScreen extends ConsumerStatefulWidget {
  const AddAddressScreen({super.key, this.initial});

  final Address? initial;

  @override
  ConsumerState<AddAddressScreen> createState() => _AddAddressScreenState();
}

class _AddAddressScreenState extends ConsumerState<AddAddressScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name);
  late final _phone = TextEditingController(text: _initialPhone);
  late final _line1 = TextEditingController(text: widget.initial?.line1);
  late final _area = TextEditingController(text: widget.initial?.area);
  late final _city = TextEditingController(text: widget.initial?.district);
  late final _state = TextEditingController(text: widget.initial?.state);
  late final _pincode = TextEditingController(text: widget.initial?.pincode);
  late final _landmark = TextEditingController(text: widget.initial?.landmark);
  late bool _isDefault = widget.initial?.isDefault ?? false;

  /// The delivery point this address will actually navigate riders to. Seeded
  /// from GPS autofill / pin-drop (or the stored pin when editing) — and shown
  /// on the form, because an INVISIBLE pin was how orders quietly went to the
  /// spot where the customer once stood instead of the address they typed.
  late double? _detectedLat = widget.initial?.latitude;
  late double? _detectedLng = widget.initial?.longitude;
  bool _locating = false;

  bool get _isEdit => widget.initial != null;

  /// On a NEW address, pre-fill the phone with the logged-in user's registered
  /// number. When editing, keep the address's existing phone.
  String? get _initialPhone {
    final existing = widget.initial?.phone;
    if (existing != null && existing.trim().isNotEmpty) return existing;
    final userPhone = ref.read(currentUserProvider)?.phone ?? '';
    return userPhone.isNotEmpty ? userPhone.localPhone : null;
  }

  /// Resolves the device location and auto-fills the address fields. The user
  /// can still edit anything afterwards.
  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    final controller = ref.read(locationControllerProvider.notifier);
    await controller.refresh();
    if (!mounted) return;

    final result = ref.read(locationControllerProvider);
    setState(() => _locating = false);

    if (result.isPermissionDenied) {
      context.showSnack('Enable location access to auto-fill your address.',
          isError: true);
      return;
    }
    final ResolvedLocation? loc = result.location;
    if (loc == null) {
      context.showSnack('Could not detect your location. Try again.',
          isError: true);
      return;
    }

    setState(() {
      _detectedLat = loc.latitude;
      _detectedLng = loc.longitude;
      if (loc.area.isNotEmpty) _area.text = loc.area;
      if (loc.city.isNotEmpty) _city.text = loc.city;
      if (loc.state.isNotEmpty) _state.text = loc.state;
      if (loc.pincode.isNotEmpty) _pincode.text = loc.pincode;
      // Seed the street line with the formatted address when it's still empty.
      if (_line1.text.trim().isEmpty && loc.formatted.isNotEmpty) {
        _line1.text = _withoutPlusCode(loc.formatted);
      }
    });
    context.showSnack('Location filled in. Review and edit if needed.');
  }

  /// Search a place and drop the pin on a map, then auto-fill the address from
  /// the confirmed point. The user can still edit anything afterwards.
  Future<void> _searchAndPin() async {
    final picked = await showLocationSearchSheet(context);
    if (picked == null || !mounted) return;
    setState(() {
      _detectedLat = picked.latitude;
      _detectedLng = picked.longitude;
      if (picked.area.isNotEmpty) _area.text = picked.area;
      if (picked.city.isNotEmpty) _city.text = picked.city;
      if (picked.state.isNotEmpty) _state.text = picked.state;
      if (picked.pincode.isNotEmpty) _pincode.text = picked.pincode;
      if (_line1.text.trim().isEmpty && picked.formatted.isNotEmpty) {
        _line1.text = _withoutPlusCode(picked.formatted);
      }
    });
    context.showSnack('Location set from map. Review and edit if needed.');
  }

  /// A reverse-geocode "formatted" string often LEADS with a Google plus-code
  /// ("V4C6+C8P, Velangi, …"). As the street line of a saved address that code is
  /// noise the customer never wrote — strip it so the seeded text reads like an
  /// address, not coordinates.
  static String _withoutPlusCode(String formatted) {
    final cleaned = formatted.replaceFirst(
        RegExp(r'^[A-Z0-9]{4,8}\+[A-Z0-9]{2,3},?\s*'), '');
    return cleaned.isEmpty ? formatted : cleaned;
  }

  /// Fine-tune the pinned delivery point on the map. This is the spot riders are
  /// sent to — the text fields are what humans read, the pin is what navigation
  /// uses, and the two must be adjustable together.
  Future<void> _adjustPin() async {
    final lat = _detectedLat;
    final lng = _detectedLng;
    if (lat == null || lng == null) return;
    final picked = await showLocationPickerSheet(
      context,
      initial: ResolvedLocation(
        latitude: lat,
        longitude: lng,
        pincode: _pincode.text.trim(),
      ),
      title: 'Adjust delivery point',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _detectedLat = picked.latitude;
      _detectedLng = picked.longitude;
    });
    context.showSnack('Delivery point updated.');
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _phone,
      _line1,
      _area,
      _city,
      _state,
      _pincode,
      _landmark,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Google Address Validation flagged the address as incomplete — let the user
  /// fix it or save anyway. Returns true to proceed.
  Future<bool> _confirmIncomplete(AddressCheck check) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Check your address'),
        content: Text(
          check.formatted.isNotEmpty
              ? 'This address looks incomplete for delivery:\n\n${check.formatted}\n\nSave it anyway?'
              : 'This address looks incomplete for delivery. Save it anyway?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Edit')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save anyway')),
        ],
      ),
    );
    return proceed ?? false;
  }

  Future<void> _save() async {
    context.hideKeyboard();
    if (!_formKey.currentState!.validate()) return;

    // Soft, non-blocking address-quality check — only prompt when Google
    // definitively flags the address as incomplete; skip silently otherwise.
    final check = await ref.read(addressValidationServiceProvider).validate(
          addressLines: [_line1.text.trim(), _area.text.trim()],
          pincode: _pincode.text.trim(),
        );
    if (!mounted) return;
    if (check.isIncomplete && !await _confirmIncomplete(check)) return;
    if (!mounted) return;

    final address = Address(
      id: widget.initial?.id ??
          'addr_${DateTime.now().millisecondsSinceEpoch}',
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      line1: _line1.text.trim(),
      area: _area.text.trim(),
      // The form has no village input, so carry the stored value through.
      // Constructing without it defaulted to '' and the PATCH sent that, wiping
      // the village off any address that had one, every time it was edited.
      village: widget.initial?.village ?? '',
      district: _city.text.trim(),
      state: _state.text.trim(),
      pincode: _pincode.text.trim(),
      landmark: _landmark.text.trim(),
      latitude: _detectedLat ?? widget.initial?.latitude,
      longitude: _detectedLng ?? widget.initial?.longitude,
      isDefault: _isDefault,
    );
    final controller = ref.read(addressesProvider.notifier);
    try {
      if (_isEdit) {
        await controller.update(address);
        if (_isDefault) await controller.setDefault(address.id);
      } else {
        await controller.add(address, makeDefault: _isDefault);
      }
    } catch (e) {
      if (!mounted) return;
      // Stay on the form so the entered details aren't lost, and surface the
      // real reason. `presentFailure` may navigate for an actionable code (e.g.
      // an expired session) — it uses `go` for those, so it can't leave a broken
      // imperative push on top of the stack.
      presentFailure(context, ref, ErrorHandler.handle(e), onRetry: _save);
      return;
    }
    // Outside the try ON PURPOSE: `pop()` throws when there's nothing to pop, and
    // with this inside the try that landed in `catch` AFTER the address had been
    // created — reporting a failure for a save that worked, and arming a Retry
    // that posted a duplicate.
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Scaffold(
      appBar: VSAppBar(
          title: _isEdit ? context.l10n.addressEdit : context.l10n.addressAdd),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: AppSpacing.screen,
          children: [
            _UseCurrentLocationButton(
              loading: _locating,
              onTap: _locating ? null : _useCurrentLocation,
            ),
            AppSpacing.vGapMd,
            VSButton(
              label: 'Search location & drop pin',
              icon: Icons.search_rounded,
              variant: VSButtonVariant.secondary,
              onPressed: _searchAndPin,
            ),
            // The pin the rider is actually sent to — visible and adjustable.
            // It used to be captured silently, so an address whose text was
            // edited after autofill kept navigating deliveries to wherever the
            // customer stood when they tapped "use my location".
            if (_detectedLat != null && _detectedLng != null) ...[
              AppSpacing.vGapMd,
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: vs.brandTint,
                  borderRadius: AppRadius.brMd,
                  border: Border.all(color: vs.brand.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.location_pin, size: 20, color: vs.brand),
                    AppSpacing.hGapSm,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Delivery point pinned',
                              style: AppTypography.labelLarge),
                          Text(
                            'Riders navigate to this pin — make sure it is on '
                            'your door, not where you are now.',
                            style: AppTypography.bodySmall
                                .copyWith(color: vs.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _adjustPin,
                      child: const Text('Adjust'),
                    ),
                  ],
                ),
              ),
            ],
            AppSpacing.vGapLg,
            VSTextField(
              controller: _name,
              label: context.l10n.addressFullName,
              hint: 'e.g. Jane Doe',
              prefixIcon: Icons.person_outline_rounded,
              validator: (v) => Validators.required(v, field: 'Name'),
            ),
            AppSpacing.vGapLg,
            VSTextField(
              controller: _phone,
              label: context.l10n.addressPhone,
              hint: '10-digit mobile number',
              prefixIcon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: Validators.phone,
            ),
            AppSpacing.vGapLg,
            VSTextField(
              controller: _line1,
              label: context.l10n.addressHouseNo,
              hint: 'e.g. 12A, Block C, Main Street',
              validator: (v) => Validators.required(v, field: 'Address'),
            ),
            AppSpacing.vGapLg,
            VSTextField(
              controller: _area,
              label: context.l10n.addressArea,
              hint: 'e.g. Sector 45',
              validator: (v) => Validators.required(v, field: 'Area'),
            ),
            AppSpacing.vGapLg,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: VSTextField(
                    controller: _city,
                    label: context.l10n.addressCity,
                    hint: 'City',
                    validator: (v) => Validators.required(v, field: 'City'),
                  ),
                ),
                AppSpacing.hGapMd,
                Expanded(
                  child: VSTextField(
                    controller: _state,
                    label: context.l10n.addressState,
                    hint: 'State',
                    validator: (v) => Validators.required(v, field: 'State'),
                  ),
                ),
              ],
            ),
            AppSpacing.vGapLg,
            VSTextField(
              controller: _pincode,
              label: context.l10n.addressPincode,
              hint: '6-digit PIN',
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: Validators.pincode,
            ),
            AppSpacing.vGapLg,
            VSTextField(
              controller: _landmark,
              label: context.l10n.addressLandmark,
              hint: 'e.g. Near City Mall',
            ),
            AppSpacing.vGapMd,
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _isDefault,
              onChanged: (v) => setState(() => _isDefault = v),
              title: Text(context.l10n.addressSetDefault,
                  style: AppTypography.bodyLarge),
              activeColor: vs.brand,
            ),
            AppSpacing.vGapLg,
            VSButton(label: context.l10n.addressSave, onPressed: _save),
            AppSpacing.vGapLg,
          ],
        ),
      ),
    );
  }
}

/// Dashed-border CTA that fills the form from the device's current location.
class _UseCurrentLocationButton extends StatelessWidget {
  const _UseCurrentLocationButton({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brMd,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: vs.brandTint,
          borderRadius: AppRadius.brMd,
          border: Border.all(color: vs.brand.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            if (loading)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: vs.brand),
              )
            else
              Icon(Icons.my_location_rounded, size: 20, color: vs.brand),
            AppSpacing.hGapMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      loading
                          ? 'Detecting location…'
                          : context.l10n.addressUseCurrentLocation,
                      style: AppTypography.labelLarge.copyWith(color: vs.brand)),
                  Text('Auto-fill area, city, state & pincode',
                      style: AppTypography.bodySmall
                          .copyWith(color: vs.textSecondary)),
                ],
              ),
            ),
            if (!loading)
              Icon(Icons.chevron_right_rounded, color: vs.brand),
          ],
        ),
      ),
    );
  }
}
