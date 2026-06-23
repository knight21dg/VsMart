import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import 'app_spacing.dart';
import 'app_typography.dart';
import 'theme_extensions.dart';

export 'app_colors.dart';
export 'app_radius.dart';
export 'app_shadows.dart';
export 'app_spacing.dart';
export 'app_typography.dart';
export 'theme_extensions.dart';

/// Central factory for VS Mart [ThemeData] (Material 3, light + dark).
abstract final class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.vsGreen,
      brightness: brightness,
      primary: AppColors.vsGreen,
      secondary: AppColors.trustBlue,
      tertiary: AppColors.offerOrange,
      error: AppColors.error,
      surface: isDark ? AppColors.cardDark : AppColors.card,
    );

    final textColor =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final textTheme = AppTypography.textTheme(textColor);
    final vsColors = isDark ? VSColors.dark : VSColors.light;

    final scaffoldBg =
        isDark ? AppColors.backgroundDark : AppColors.background;
    final cardBg = isDark ? AppColors.cardDark : AppColors.card;
    final borderColor = isDark ? AppColors.borderDark : AppColors.border;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBg,
      textTheme: textTheme,
      fontFamily: AppTypography.bodyFont,
      extensions: <ThemeExtension<dynamic>>[vsColors],
      splashFactory: InkRipple.splashFactory,

      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        surfaceTintColor: AppColors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        iconTheme: IconThemeData(color: textColor),
        titleTextStyle: AppTypography.headlineSmall.copyWith(color: textColor),
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),

      cardTheme: CardThemeData(
        color: cardBg,
        surfaceTintColor: AppColors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brLg),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.vsGreen,
          foregroundColor: AppColors.white,
          disabledBackgroundColor: AppColors.disabled,
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          textStyle: AppTypography.labelLarge,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.vsGreen,
          minimumSize: const Size.fromHeight(52),
          side: const BorderSide(color: AppColors.vsGreen, width: 1.5),
          textStyle: AppTypography.labelLarge,
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.vsGreen,
          textStyle: AppTypography.labelLarge,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardBg,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        hintStyle: AppTypography.bodyMedium.copyWith(
          color: vsColors.textSecondary,
        ),
        labelStyle: AppTypography.bodyMedium.copyWith(
          color: vsColors.textSecondary,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: AppColors.vsGreen, width: 1.5),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: AppRadius.brMd,
          borderSide: BorderSide(color: AppColors.error, width: 1.5),
        ),
        errorStyle: AppTypography.bodySmall.copyWith(color: AppColors.error),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: cardBg,
        side: BorderSide(color: borderColor),
        labelStyle: AppTypography.labelMedium.copyWith(color: textColor),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brPill),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
      ),

      dividerTheme: DividerThemeData(
        color: borderColor,
        thickness: 1,
        space: 1,
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: cardBg,
        selectedItemColor: AppColors.vsGreen,
        unselectedItemColor: vsColors.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        showUnselectedLabels: true,
        selectedLabelStyle: AppTypography.labelSmall,
        unselectedLabelStyle: AppTypography.labelSmall,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardBg,
        surfaceTintColor: AppColors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.bottomSheet),
        showDragHandle: true,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: cardBg,
        surfaceTintColor: AppColors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brXl),
        titleTextStyle: AppTypography.headlineSmall.copyWith(color: textColor),
        contentTextStyle: AppTypography.bodyMedium.copyWith(color: textColor),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppColors.card : AppColors.textPrimary,
        contentTextStyle: AppTypography.bodyMedium.copyWith(
          color: isDark ? AppColors.textPrimary : AppColors.white,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.vsGreen,
      ),

      iconTheme: IconThemeData(color: textColor),
      scrollbarTheme: const ScrollbarThemeData(
        thickness: WidgetStatePropertyAll(4),
      ),
    );
  }
}
