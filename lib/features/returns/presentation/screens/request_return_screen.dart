import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/widgets.dart';
import '../providers/returns_providers.dart';

/// Return / refund request form for a delivered order. Submits to
/// `/orders/{orderCode}/returns`; on success it refreshes the returns list and
/// pops back. Mirrors [RaiseTicketScreen]'s structure.
class RequestReturnScreen extends ConsumerStatefulWidget {
  const RequestReturnScreen({super.key, required this.orderCode});

  final String orderCode;

  @override
  ConsumerState<RequestReturnScreen> createState() =>
      _RequestReturnScreenState();
}

class _RequestReturnScreenState extends ConsumerState<RequestReturnScreen> {
  static const _reasons = [
    'Damaged item',
    'Wrong item',
    'Quality issue',
    'Changed my mind',
    'Other',
  ];
  static const _maxDescription = 500;

  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();

  String? _reason;
  int _descriptionLength = 0;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _description.addListener(_onDescriptionChanged);
  }

  @override
  void dispose() {
    _description
      ..removeListener(_onDescriptionChanged)
      ..dispose();
    super.dispose();
  }

  void _onDescriptionChanged() {
    final length = _description.text.characters.length;
    if (length != _descriptionLength) {
      setState(() => _descriptionLength = length);
    }
  }

  Future<void> _submit() async {
    context.hideKeyboard();
    if (!_formKey.currentState!.validate() || _submitting) return;
    setState(() => _submitting = true);
    try {
      final result = await ref.read(returnsDataSourceProvider).create(
            orderCode: widget.orderCode,
            reason: _reason ?? 'Other',
            description: _description.text.trim(),
          );
      if (!mounted) return;
      if (result.ok) {
        ref.invalidate(returnsProvider);
        context.showSnack(result.message);
        context.pop();
      } else {
        setState(() => _submitting = false);
        context.showSnack(result.message, isError: true);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      context.showSnack('Could not request a return. Please try again.',
          isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const VSAppBar(title: 'Return / Refund'),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: AppSpacing.screen,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Order', style: AppTypography.labelLarge),
                            AppSpacing.vGapSm,
                            Text(
                              widget.orderCode.isEmpty
                                  ? '—'
                                  : widget.orderCode,
                              style: AppTypography.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      AppSpacing.vGapLg,
                      _SectionCard(
                        child: _DropdownField(
                          label: 'Reason for Return',
                          required: true,
                          hint: 'Select a reason',
                          value: _reason,
                          items: _reasons,
                          onChanged: (v) => setState(() => _reason = v),
                          validator: (v) =>
                              Validators.required(v, field: 'Reason'),
                        ),
                      ),
                      AppSpacing.vGapLg,
                      _SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('Description (Optional)',
                                    style: AppTypography.labelLarge),
                                const Spacer(),
                                Text(
                                  '$_descriptionLength/$_maxDescription',
                                  style: AppTypography.bodySmall.copyWith(
                                    color: context.vsColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            AppSpacing.vGapSm,
                            VSTextField(
                              controller: _description,
                              hint: 'Tell us more about the issue...',
                              maxLines: 5,
                              maxLength: _maxDescription,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _BottomBar(onSubmit: _submit, isLoading: _submitting),
          ],
        ),
      ),
    );
  }
}

/// White rounded container that groups a labeled form section.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: context.vsColors.border),
      ),
      child: child,
    );
  }
}

/// A label with a trailing red asterisk to mark required fields.
class _RequiredLabel extends StatelessWidget {
  const _RequiredLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: label,
        style: AppTypography.labelLarge,
        children: [
          TextSpan(
            text: ' *',
            style: AppTypography.labelLarge.copyWith(color: AppColors.error),
          ),
        ],
      ),
    );
  }
}

/// Theme-styled dropdown that matches [VSTextField]'s look.
class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.hint,
    required this.value,
    required this.items,
    required this.onChanged,
    this.required = false,
    this.validator,
  });

  final String label;
  final String hint;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  final bool required;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (required)
          _RequiredLabel(label)
        else
          Text(label, style: AppTypography.labelLarge),
        AppSpacing.vGapSm,
        DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          hint: Text(
            hint,
            style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
          ),
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: vs.textSecondary),
          style:
              AppTypography.bodyMedium.copyWith(color: context.colors.onSurface),
          validator: validator,
          items: [
            for (final item in items)
              DropdownMenuItem(value: item, child: Text(item)),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Sticky bottom action bar with Cancel and Submit buttons.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.onSubmit, required this.isLoading});

  final VoidCallback onSubmit;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.screen,
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: context.vsColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: VSOutlinedButton(
              label: 'Cancel',
              onPressed: isLoading ? null : () => context.pop(),
            ),
          ),
          AppSpacing.hGapMd,
          Expanded(
            flex: 2,
            child: VSButton(
              label: 'Submit Request',
              isLoading: isLoading,
              onPressed: onSubmit,
            ),
          ),
        ],
      ),
    );
  }
}
