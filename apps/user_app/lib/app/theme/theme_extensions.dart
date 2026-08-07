import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Custom semantic colors that are not part of Material's [ColorScheme] but are
/// required throughout VS Mart (brand accents, status tints, surfaces).
///
/// Access via `Theme.of(context).extension<VSColors>()!` or the
/// `context.vsColors` extension getter.
@immutable
class VSColors extends ThemeExtension<VSColors> {
  const VSColors({
    required this.brand,
    required this.trust,
    required this.offer,
    required this.success,
    required this.warning,
    required this.danger,
    required this.brandTint,
    required this.trustTint,
    required this.offerTint,
    required this.successTint,
    required this.dangerTint,
    required this.border,
    required this.textSecondary,
    required this.shimmerBase,
    required this.shimmerHighlight,
  });

  final Color brand;
  final Color trust;
  final Color offer;
  final Color success;
  final Color warning;
  final Color danger;

  final Color brandTint;
  final Color trustTint;
  final Color offerTint;
  final Color successTint;
  final Color dangerTint;

  final Color border;
  final Color textSecondary;
  final Color shimmerBase;
  final Color shimmerHighlight;

  static const VSColors light = VSColors(
    brand: AppColors.vsGreen,
    trust: AppColors.trustBlue,
    offer: AppColors.offerOrange,
    success: AppColors.success,
    warning: AppColors.warning,
    danger: AppColors.error,
    brandTint: AppColors.greenTint,
    trustTint: AppColors.blueTint,
    offerTint: AppColors.orangeTint,
    successTint: AppColors.greenTint,
    dangerTint: AppColors.redTint,
    border: AppColors.border,
    textSecondary: AppColors.textSecondary,
    shimmerBase: AppColors.shimmerBase,
    shimmerHighlight: AppColors.shimmerHighlight,
  );

  static const VSColors dark = VSColors(
    brand: AppColors.vsGreen,
    trust: AppColors.trustBlue,
    offer: AppColors.offerOrange,
    success: AppColors.success,
    warning: AppColors.warning,
    danger: AppColors.error,
    brandTint: Color(0xFF14361F),
    trustTint: Color(0xFF13294D),
    offerTint: Color(0xFF3D2410),
    successTint: Color(0xFF14361F),
    dangerTint: Color(0xFF3D1717),
    border: AppColors.borderDark,
    textSecondary: AppColors.textSecondaryDark,
    shimmerBase: AppColors.cardDark,
    shimmerHighlight: AppColors.borderDark,
  );

  @override
  VSColors copyWith({
    Color? brand,
    Color? trust,
    Color? offer,
    Color? success,
    Color? warning,
    Color? danger,
    Color? brandTint,
    Color? trustTint,
    Color? offerTint,
    Color? successTint,
    Color? dangerTint,
    Color? border,
    Color? textSecondary,
    Color? shimmerBase,
    Color? shimmerHighlight,
  }) {
    return VSColors(
      brand: brand ?? this.brand,
      trust: trust ?? this.trust,
      offer: offer ?? this.offer,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      brandTint: brandTint ?? this.brandTint,
      trustTint: trustTint ?? this.trustTint,
      offerTint: offerTint ?? this.offerTint,
      successTint: successTint ?? this.successTint,
      dangerTint: dangerTint ?? this.dangerTint,
      border: border ?? this.border,
      textSecondary: textSecondary ?? this.textSecondary,
      shimmerBase: shimmerBase ?? this.shimmerBase,
      shimmerHighlight: shimmerHighlight ?? this.shimmerHighlight,
    );
  }

  @override
  VSColors lerp(ThemeExtension<VSColors>? other, double t) {
    if (other is! VSColors) return this;
    return VSColors(
      brand: Color.lerp(brand, other.brand, t)!,
      trust: Color.lerp(trust, other.trust, t)!,
      offer: Color.lerp(offer, other.offer, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      brandTint: Color.lerp(brandTint, other.brandTint, t)!,
      trustTint: Color.lerp(trustTint, other.trustTint, t)!,
      offerTint: Color.lerp(offerTint, other.offerTint, t)!,
      successTint: Color.lerp(successTint, other.successTint, t)!,
      dangerTint: Color.lerp(dangerTint, other.dangerTint, t)!,
      border: Color.lerp(border, other.border, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      shimmerBase: Color.lerp(shimmerBase, other.shimmerBase, t)!,
      shimmerHighlight: Color.lerp(shimmerHighlight, other.shimmerHighlight, t)!,
    );
  }
}
