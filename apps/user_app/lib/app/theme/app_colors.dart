import 'package:flutter/material.dart';

/// VS Mart brand color palette.
///
/// All colors used across the app must be sourced from here so the design
/// system stays consistent and theming (light/dark) remains centralized.
abstract final class AppColors {
  AppColors._();

  // ----- Brand -----
  static const Color vsGreen = Color(0xFF16A34A); // Primary brand
  static const Color trustBlue = Color(0xFF2563EB); // Secondary / credit
  static const Color offerOrange = Color(0xFFF97316); // Promotions / offers

  // ----- Semantic -----
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFDC2626);
  static const Color info = trustBlue;

  // ----- Neutrals (Light) -----
  static const Color background = Color(0xFFF8FAFC);
  static const Color card = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color border = Color(0xFFE2E8F0);

  // ----- Neutrals (Dark) — neutral charcoal for a premium feel -----
  static const Color backgroundDark = Color(0xFF0E1116);
  static const Color cardDark = Color(0xFF1A1F27);
  static const Color textPrimaryDark = Color(0xFFF3F5F7);
  static const Color textSecondaryDark = Color(0xFF98A2B3);
  static const Color borderDark = Color(0xFF2A313C);

  // ----- Utility -----
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color transparent = Color(0x00000000);
  static const Color disabled = Color(0xFFCBD5E1);
  static const Color overlay = Color(0x66000000);
  static const Color shimmerBase = Color(0xFFE2E8F0);
  static const Color shimmerHighlight = Color(0xFFF1F5F9);

  // ----- Tints (subtle backgrounds for chips / banners) -----
  static const Color greenTint = Color(0xFFDCFCE7);
  static const Color blueTint = Color(0xFFDBEAFE);
  static const Color orangeTint = Color(0xFFFFEDD5);
  static const Color redTint = Color(0xFFFEE2E2);
  static const Color amberTint = Color(0xFFFEF3C7);

  // ----- Gradients -----
  static const LinearGradient greenGradient = LinearGradient(
    colors: [Color(0xFF16A34A), Color(0xFF22C55E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient creditGradient = LinearGradient(
    colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient offerGradient = LinearGradient(
    colors: [Color(0xFFF97316), Color(0xFFFB923C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
