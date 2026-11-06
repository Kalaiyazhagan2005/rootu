import 'package:flutter/material.dart';

class AppTheme {
  // Brand Color Palette (from RootU Design Specs)
  static const Color primaryDark = Color(0xFF0F2D23);      // #0F2D23
  static const Color primaryGreen = Color(0xFF2E7D32);     // #2E7D32
  static const Color accentLightGreen = Color(0xFFA7C957); // #A7C957
  static const Color backgroundCream = Color(0xFFF6F8F4);  // #F6F8F4
  static const Color cardWhite = Color(0xFFFFFFFF);
  static const Color inputBorder = Color(0xFFE2E8DF);
  static const Color inputFill = Color(0xFFF9FAF8);
  static const Color textPrimary = Color(0xFF0F2D23);
  static const Color textSecondary = Color(0xFF5C6B64);
  static const Color textHint = Color(0xFFA0ACA4);
  static const Color errorRed = Color(0xFFD32F2F);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: backgroundCream,
      primaryColor: primaryDark,
      colorScheme: const ColorScheme.light(
        primary: primaryDark,
        secondary: primaryGreen,
        tertiary: accentLightGreen,
        surface: cardWhite,
        error: errorRed,
        onPrimary: Colors.white,
        onSurface: textPrimary,
      ),
      fontFamily: 'Inter',
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: primaryDark),
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
