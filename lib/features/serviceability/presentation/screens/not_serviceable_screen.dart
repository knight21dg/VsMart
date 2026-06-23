import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../providers/serviceability_providers.dart';

/// Shown when the customer's location falls outside every serviceable zone
/// (spec §NOT SERVICEABLE FLOW). Offers: change location, notify-me (captured as
/// an expansion request), and contact support.
class NotServiceableScreen extends ConsumerWidget {
  const NotServiceableScreen({super.key, this.latitude, this.longitude, this.pincode});

  final double? latitude;
  final double? longitude;
  final String? pincode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    return Scaffold(
      appBar: const VSAppBar(title: 'Delivery area'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.xl),
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
                'We are not available in your area yet',
                textAlign: TextAlign.center,
                style: AppTypography.headlineMedium,
              ),
              AppSpacing.vGapSm,
              Text(
                "VS Mart is expanding fast. Tell us where you are and we'll "
                'notify you the moment we start delivering near you.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xxl),
              VSButton(
                label: 'Change location',
                icon: Icons.edit_location_alt_rounded,
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.goNamed(RouteNames.addresses);
                  }
                },
              ),
              AppSpacing.vGapMd,
              VSOutlinedButton(
                label: 'Notify me when you arrive',
                icon: Icons.notifications_active_outlined,
                onPressed: () => _openNotifySheet(context, ref),
              ),
              AppSpacing.vGapMd,
              VSButton(
                label: 'Contact support',
                variant: VSButtonVariant.neutral,
                icon: Icons.support_agent_rounded,
                onPressed: () => context.goNamed(RouteNames.support),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openNotifySheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) => _NotifyMeSheet(
        latitude: latitude,
        longitude: longitude,
        pincode: pincode ?? '',
      ),
    );
  }
}

class _NotifyMeSheet extends ConsumerStatefulWidget {
  const _NotifyMeSheet({this.latitude, this.longitude, this.pincode = ''});

  final double? latitude;
  final double? longitude;
  final String pincode;

  @override
  ConsumerState<_NotifyMeSheet> createState() => _NotifyMeSheetState();
}

class _NotifyMeSheetState extends ConsumerState<_NotifyMeSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _area = TextEditingController();
  late final _pincode = TextEditingController(text: widget.pincode);
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _area.dispose();
    _pincode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await ref.read(serviceabilityDataSourceProvider).requestExpansion(
            name: _name.text.trim(),
            mobile: _mobile.text.trim(),
            area: _area.text.trim(),
            pincode: _pincode.text.trim(),
            latitude: widget.latitude,
            longitude: widget.longitude,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      context.showSnack(
        "Thanks! We'll let you know when VS Mart reaches your area.",
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      context.showSnack('Could not submit. Please try again.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg + bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Notify me when you arrive',
                style: AppTypography.titleLarge),
            AppSpacing.vGapSm,
            Text(
              'Share your details so we can reach out as soon as we launch '
              'near you.',
              style: AppTypography.bodySmall
                  .copyWith(color: context.vsColors.textSecondary),
            ),
            AppSpacing.vGapLg,
            VSTextField(
              controller: _name,
              label: 'Name',
              hint: 'Your name',
              textInputAction: TextInputAction.next,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
            ),
            AppSpacing.vGapMd,
            VSTextField(
              controller: _mobile,
              label: 'Mobile number',
              hint: '10-digit mobile',
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              validator: (v) => (v == null || v.trim().length < 10)
                  ? 'Enter a valid 10-digit mobile'
                  : null,
            ),
            AppSpacing.vGapMd,
            VSTextField(
              controller: _area,
              label: 'Area / village',
              hint: 'Your locality',
              textInputAction: TextInputAction.next,
            ),
            AppSpacing.vGapMd,
            VSTextField(
              controller: _pincode,
              label: 'Pincode',
              hint: '6-digit pincode',
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
            ),
            AppSpacing.vGapXl,
            VSButton(
              label: 'Submit',
              isLoading: _submitting,
              onPressed: _submitting ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
