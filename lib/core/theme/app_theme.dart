import 'package:flutter/material.dart';

import 'app_colors.dart';

// [REF: DESIGN_TOKENS]
/// Assembles the app's [ThemeData] and re-exports the colour tokens under the
/// names widgets already use.
///
/// The colours themselves are defined once in [AppColors] — these are aliases,
/// kept so that renaming every `AppTheme.primary` call site is a separate
/// change from introducing the token file. New code should prefer [AppColors]
/// directly; both resolve to the same constant.
class AppTheme {
  /// Was `#10B981`, the Excellent-band emerald, until 2026-10-04. See the
  /// brand note in [AppColors] for the three reasons it moved.
  static const Color primary = AppColors.brand;
  static const Color primaryDark = AppColors.brandStrong;
  static const Color secondary = AppColors.textPrimary;
  static const Color accent = AppColors.brandSurface;
  static const Color background = AppColors.background;
  static const Color surface = AppColors.surface;

  static const Color textPrimary = AppColors.textPrimary;
  static const Color textSecondary = AppColors.textSecondary;
  static const Color border = AppColors.border;

  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: AppColors.textPrimary.withAlpha(15),
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: AppColors.textPrimary.withAlpha(8),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ];

  static BoxDecoration glassDecoration(Color baseColor) => BoxDecoration(
        color: baseColor.withAlpha(180),
        borderRadius: cardRadius,
        border: Border.all(color: Colors.white.withAlpha(128), width: 0.5),
        boxShadow: softShadow,
      );

  static final BorderRadius cardRadius = BorderRadius.circular(16);
  static final BorderRadius buttonRadius = BorderRadius.circular(12);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: '.SF Pro Display',
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: secondary,
        surface: surface,
        surfaceContainerHighest: accent,
        onPrimary: Colors.white,
        onSurface: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: '.SF Pro Display',
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.5,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: secondary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: buttonRadius,
          ),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: const TextStyle(
            fontFamily: '.SF Pro Display',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          side: const BorderSide(color: border),
          shape: RoundedRectangleBorder(
            borderRadius: buttonRadius,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: const TextStyle(
            fontFamily: '.SF Pro Display',
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: cardRadius,
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        space: 1,
        thickness: 1,
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontWeight: FontWeight.w800,
          color: textPrimary,
          letterSpacing: -1.0,
          fontSize: 28,
        ),
        headlineSmall: TextStyle(
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.8,
          fontSize: 24,
        ),
        titleLarge: TextStyle(
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.5,
          fontSize: 20,
        ),
        titleMedium: TextStyle(
          fontWeight: FontWeight.w600,
          color: textPrimary,
          letterSpacing: -0.3,
          fontSize: 16,
        ),
        bodyLarge: TextStyle(
          fontWeight: FontWeight.w500,
          color: textPrimary,
          fontSize: 16,
        ),
        bodyMedium: TextStyle(
          fontWeight: FontWeight.w400,
          color: textSecondary,
          fontSize: 14,
        ),
        labelLarge: TextStyle(
          fontWeight: FontWeight.w600,
          color: textPrimary,
          fontSize: 14,
        ),
      ),
    );
  }
}
