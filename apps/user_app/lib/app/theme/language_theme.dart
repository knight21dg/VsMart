import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Language-aware typography resolver (spec §Enterprise Typography Architecture).
///
///   en → Plus Jakarta Sans
///   te → Noto Sans Telugu
///   hi → Noto Sans Devanagari
///
/// We keep **Plus Jakarta Sans** as the Latin/number primary and register the two
/// Noto Indic fonts as fallbacks, so:
///   • Telugu / Devanagari glyphs always render in their proper font (even on an
///     English-primary screen), and
///   • numbers + currency (₹25,000) stay in Plus Jakarta on Telugu/Hindi screens
///     — exactly the consistent-numbers rule the design calls for.
abstract final class LanguageThemeResolver {
  LanguageThemeResolver._();

  /// Fallback families (GoogleFonts registers them on first build). Order matters:
  /// Latin first, then the Indic scripts.
  static final List<String> fallbacks = <String>[
    GoogleFonts.plusJakartaSans().fontFamily!,
    GoogleFonts.notoSansTelugu().fontFamily!,
    GoogleFonts.notoSansDevanagari().fontFamily!,
  ];

  /// The primary font family for a locale (used for [ThemeData.fontFamily]).
  static String primaryFamily(String localeCode) => switch (localeCode) {
        'te' => GoogleFonts.notoSansTelugu().fontFamily!,
        'hi' => GoogleFonts.notoSansDevanagari().fontFamily!,
        _ => GoogleFonts.plusJakartaSans().fontFamily!,
      };

  /// A primary [TextStyle] for a locale with the Indic fallbacks attached.
  static TextStyle style(
    String localeCode, {
    required double size,
    required FontWeight weight,
    double? height,
    double? letterSpacing,
    Color? color,
  }) {
    final builder = switch (localeCode) {
      'te' => GoogleFonts.notoSansTelugu,
      'hi' => GoogleFonts.notoSansDevanagari,
      _ => GoogleFonts.plusJakartaSans,
    };
    return builder(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      color: color,
    ).copyWith(fontFamilyFallback: fallbacks);
  }
}
