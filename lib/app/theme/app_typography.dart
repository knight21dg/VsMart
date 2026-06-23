import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// VS Mart typography scale.
///
/// Headings/display use **Poppins**, body/UI text uses **Inter**.
/// Colors are intentionally omitted on most styles so they inherit from the
/// active [TextTheme]; use the helpers for explicit colored text.
abstract final class AppTypography {
  AppTypography._();

  static const String displayFont = 'Poppins';
  static const String bodyFont = 'Inter';

  static TextStyle _poppins({
    required double size,
    required FontWeight weight,
    double? height,
    double? letterSpacing,
    Color? color,
  }) =>
      GoogleFonts.poppins(
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: letterSpacing,
        color: color,
      );

  static TextStyle _inter({
    required double size,
    required FontWeight weight,
    double? height,
    double? letterSpacing,
    Color? color,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: letterSpacing,
        color: color,
      );

  // ----- Display / Headings (Poppins) -----
  // Cached as `static final` so each GoogleFonts TextStyle is built once, not
  // recreated on every widget rebuild (these are read constantly across the UI).
  static final TextStyle displayLarge =
      _poppins(size: 32, weight: FontWeight.w700, height: 1.2);
  static final TextStyle displayMedium =
      _poppins(size: 28, weight: FontWeight.w700, height: 1.2);
  static final TextStyle headlineLarge =
      _poppins(size: 24, weight: FontWeight.w600, height: 1.25);
  static final TextStyle headlineMedium =
      _poppins(size: 20, weight: FontWeight.w600, height: 1.3);
  static final TextStyle headlineSmall =
      _poppins(size: 18, weight: FontWeight.w600, height: 1.3);
  static final TextStyle titleLarge =
      _poppins(size: 16, weight: FontWeight.w600, height: 1.4);
  static final TextStyle titleMedium =
      _poppins(size: 14, weight: FontWeight.w600, height: 1.4);

  // ----- Body / UI (Inter) -----
  static final TextStyle bodyLarge =
      _inter(size: 16, weight: FontWeight.w400, height: 1.5);
  static final TextStyle bodyMedium =
      _inter(size: 14, weight: FontWeight.w400, height: 1.5);
  static final TextStyle bodySmall =
      _inter(size: 12, weight: FontWeight.w400, height: 1.5);
  static final TextStyle labelLarge =
      _inter(size: 14, weight: FontWeight.w600, height: 1.4);
  static final TextStyle labelMedium =
      _inter(size: 12, weight: FontWeight.w600, height: 1.4);
  static final TextStyle labelSmall =
      _inter(size: 11, weight: FontWeight.w500, height: 1.4, letterSpacing: 0.2);

  // ----- Numeric / price emphasis -----
  static final TextStyle priceLarge =
      _poppins(size: 22, weight: FontWeight.w700, height: 1.2);
  static final TextStyle priceMedium =
      _poppins(size: 16, weight: FontWeight.w700, height: 1.2);

  /// Build the Material [TextTheme] for a given default text [color].
  static TextTheme textTheme(Color color) {
    final t = TextTheme(
      displayLarge: displayLarge,
      displayMedium: displayMedium,
      headlineLarge: headlineLarge,
      headlineMedium: headlineMedium,
      headlineSmall: headlineSmall,
      titleLarge: titleLarge,
      titleMedium: titleMedium,
      bodyLarge: bodyLarge,
      bodyMedium: bodyMedium,
      bodySmall: bodySmall,
      labelLarge: labelLarge,
      labelMedium: labelMedium,
      labelSmall: labelSmall,
    );
    return t.apply(bodyColor: color, displayColor: color);
  }

  static TextTheme get lightTextTheme => textTheme(AppColors.textPrimary);
  static TextTheme get darkTextTheme => textTheme(AppColors.textPrimaryDark);
}
