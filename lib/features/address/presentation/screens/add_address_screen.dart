import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/string_extensions.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../auth/presentation/providers/current_user_provider.dart';
import '../../../location/domain/entities/resolved_location.dart';
import '../../../location/presentation/providers/location_providers.dart';
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

  /// Captured GPS for the address being created via "Use my current location".
  double? _detectedLat;
  double? _detectedLng;
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
        _line1.text = loc.formatted;
      }
    });
    context.showSnack('Location filled in. Review and edit if needed.');
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

  Future<void> _save() async {
    context.hideKeyboard();
    if (!_formKey.currentState!.validate()) return;
    final address = Address(
      id: widget.initial?.id ??
          'addr_${DateTime.now().millisecondsSinceEpoch}',
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      line1: _line1.text.trim(),
      area: _area.text.trim(),
      district: _city.text.trim(),
      state: _state.text.trim(),
      pincode: _pincode.text.trim(),
      landmark: _landmark.text.trim(),
      latitude: _detectedLat ?? widget.initial?.latitude,
      longitude: _detectedLng ?? widget.initial?.longitude,
      isDefault: _isDefault,
    );
    final controller = ref.read(addressesProvider.notifier);
    if (_isEdit) {
      await controller.update(address);
      if (_isDefault) await controller.setDefault(address.id);
    } else {
      await controller.add(address, makeDefault: _isDefault);
    }
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Scaffold(
      appBar: VSAppBar(title: _isEdit ? 'Edit Address' : 'Add Address'),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: AppSpacing.screen,
          children: [
            _UseCurrentLocationButton(
              loading: _locating,
              onTap: _locating ? null : _useCurrentLocation,
            ),
            AppSpacing.vGapLg,
            VSTextField(
              controller: _name,
              label: 'Full Name',
              hint: 'e.g. Jane Doe',
              prefixIcon: Icons.person_outline_rounded,
              validator: (v) => Validators.required(v, field: 'Name'),
            ),
            AppSpacing.vGapLg,
            VSTextField(
              controller: _phone,
              label: 'Phone Number',
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
              label: 'House / Flat / Street',
              hint: 'e.g. 12A, Block C, Main Street',
              validator: (v) => Validators.required(v, field: 'Address'),
            ),
            AppSpacing.vGapLg,
            VSTextField(
              controller: _area,
              label: 'Area / Locality',
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
                    label: 'City',
                    hint: 'City',
                    validator: (v) => Validators.required(v, field: 'City'),
                  ),
                ),
                AppSpacing.hGapMd,
                Expanded(
                  child: VSTextField(
                    controller: _state,
                    label: 'State',
                    hint: 'State',
                    validator: (v) => Validators.required(v, field: 'State'),
                  ),
                ),
              ],
            ),
            AppSpacing.vGapLg,
            VSTextField(
              controller: _pincode,
              label: 'Pincode',
              hint: '6-digit PIN',
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: Validators.pincode,
            ),
            AppSpacing.vGapLg,
            VSTextField(
              controller: _landmark,
              label: 'Landmark (Optional)',
              hint: 'e.g. Near City Mall',
            ),
            AppSpacing.vGapMd,
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _isDefault,
              onChanged: (v) => setState(() => _isDefault = v),
              title: Text('Set as default address',
                  style: AppTypography.bodyLarge),
              activeColor: vs.brand,
            ),
            AppSpacing.vGapLg,
            VSButton(label: 'Save Address', onPressed: _save),
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
                  Text(loading ? 'Detecting location…' : 'Use my current location',
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
