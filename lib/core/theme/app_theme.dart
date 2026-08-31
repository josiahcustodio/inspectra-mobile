import 'package:flutter/material.dart';

class AppTheme {
  static const Color primary = Color(0xFF10B981);
  static const Color primaryDark = Color(0xFF059669);
  static const Color secondary = Color(0xFF1A1C1E);
  static const Color accent = Color(0xFFECFDF5);
  static const Color background = Color(0xFFF8FAFC);
  static const Color surface = Colors.white;
  
  static const Color textPrimary = Color(0xFF1A1C1E);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color border = Color(0xFFE2E8F0);

  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: const Color(0xFF1A1C1E).withAlpha(15),
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: const Color(0xFF1A1C1E).withAlpha(8),
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
  static final BorderRadius smallRadius = BorderRadius.circular(8);

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
