import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/constants/app_constants.dart';
import '../../app/theme/app_theme.dart';
import '../extensions/context_extensions.dart';

/// Phone-number input with a fixed country-code prefix.
class VSPhoneField extends StatelessWidget {
  const VSPhoneField({
    super.key,
    this.controller,
    this.label = 'Phone Number',
    this.hint = 'Enter your mobile number',
    this.countryCode = AppConstants.defaultCountryCode,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.autofocus = false,
  });

  final TextEditingController? controller;
  final String label;
  final String hint;
  final String countryCode;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.labelMedium),
        AppSpacing.vGapSm,
        TextFormField(
          controller: controller,
          enabled: enabled,
          autofocus: autofocus,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          maxLength: AppConstants.phoneNumberLength,
          validator: validator,
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(AppConstants.phoneNumberLength),
          ],
          style: AppTypography.bodyMedium
              .copyWith(color: context.textStyles.bodyLarge?.color),
          decoration: InputDecoration(
            hintText: hint,
            counterText: '',
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.sm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(countryCode,
                      style: AppTypography.bodyMedium.copyWith(
                          color: context.textStyles.bodyLarge?.color)),
                  AppSpacing.hGapSm,
                  Container(width: 1, height: 22, color: vs.border),
                ],
              ),
            ),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 0, minHeight: 0),
          ),
        ),
      ],
    );
  }
}
