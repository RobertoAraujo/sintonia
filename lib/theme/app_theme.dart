// THEME LOCK: light — source: domain signal (consumer social, accessibility)
// Scaffold.backgroundColor = AppTheme.background — ALL screens

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Primary palette — warm teal (calm, nature-inspired, accessible)
  static const Color primary = Color(0xFF2D7D6F);
  static const Color primaryLight = Color(0xFF3D9E8E);
  static const Color primaryContainer = Color(0xFFB2DFD8);
  static const Color onPrimaryContainer = Color(0xFF003D35);

  // Secondary palette — soft lavender (neurodivergent community)
  static const Color secondary = Color(0xFF7C6FC4);
  static const Color secondaryContainer = Color(0xFFE3DFFF);
  static const Color onSecondaryContainer = Color(0xFF1D0060);

  // Semantic colors
  static const Color success = Color(0xFF2D7A4F);
  static const Color warning = Color(0xFFB45309);
  static const Color error = Color(0xFFB91C1C);
  static const Color info = Color(0xFF1B4FD8);

  // Light surfaces
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceVariantLight = Color(0xFFF5F7F6);
  static const Color backgroundLight = Color(0xFFF0F3F2);
  static const Color outlineLight = Color(0xFFCDD8D4);
  static const Color outlineVariantLight = Color(0xFFE8EFEC);

  // Dark surfaces
  static const Color surfaceDark = Color(0xFF1E2422);
  static const Color surfaceVariantDark = Color(0xFF2A3330);
  static const Color backgroundDark = Color(0xFF141918);
  static const Color outlineDark = Color(0xFF3D4F4A);
  static const Color outlineVariantDark = Color(0xFF2A3A35);

  // Neurodivergence type colors
  static const Color teaColor = Color(0xFF4A90D9);
  static const Color tdahColor = Color(0xFFE8A020);
  static const Color dyslexiaColor = Color(0xFF9B59B6);
  static const Color touretteColor = Color(0xFF27AE60);

  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: primaryContainer,
      onPrimaryContainer: onPrimaryContainer,
      secondary: secondary,
      onSecondary: Colors.white,
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: onSecondaryContainer,
      surface: surfaceLight,
      onSurface: Color(0xFF1A2420),
      surfaceContainerHighest: surfaceVariantLight,
      onSurfaceVariant: Color(0xFF4A5955),
      error: error,
      onError: Colors.white,
      outline: outlineLight,
      outlineVariant: outlineVariantLight,
      inverseSurface: Color(0xFF2E3532),
      onInverseSurface: Color(0xFFF0F3F2),
    ),
    scaffoldBackgroundColor: backgroundLight,
    textTheme: GoogleFonts.nunitoSansTextTheme(
      const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
        displaySmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        headlineLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        headlineSmall: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w400),
        bodyMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
        bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
        labelLarge: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
        labelMedium: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        labelSmall: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    ),
    appBarTheme: AppBarThemeData(
      backgroundColor: backgroundLight,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.nunitoSans(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF1A2420),
      ),
      iconTheme: const IconThemeData(color: Color(0xFF1A2420)),
    ),
    cardTheme: CardThemeData(
      color: surfaceLight,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: outlineVariantLight, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surfaceVariantLight,
      selectedColor: primaryContainer,
      labelStyle: GoogleFonts.nunitoSans(
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
      side: const BorderSide(color: outlineLight),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: false,
      border: const UnderlineInputBorder(
        borderSide: BorderSide(color: outlineLight),
      ),
      enabledBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: outlineLight),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: primary, width: 2),
      ),
      labelStyle: GoogleFonts.nunitoSans(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: const Color(0xFF4A5955),
      ),
      hintStyle: GoogleFonts.nunitoSans(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: const Color(0xFF9BA8A3),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: Colors.white,
      elevation: 4,
      shape: CircleBorder(),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surfaceLight,
      indicatorColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return GoogleFonts.nunitoSans(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: primary,
          );
        }
        return GoogleFonts.nunitoSans(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          color: const Color(0xFF9BA8A3),
        );
      }),
    ),
    dividerTheme: const DividerThemeData(
      color: outlineVariantLight,
      thickness: 1,
      space: 1,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: surfaceLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
  );

  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.dark(
      primary: primaryLight,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFF1A5A50),
      onPrimaryContainer: Color(0xFFB2DFD8),
      secondary: Color(0xFF9D92E0),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFF3D3480),
      onSecondaryContainer: Color(0xFFE3DFFF),
      surface: surfaceDark,
      onSurface: Color(0xFFE6EEEB),
      surfaceContainerHighest: surfaceVariantDark,
      onSurfaceVariant: Color(0xFFB0BDB9),
      error: Color(0xFFCF6679),
      onError: Colors.white,
      outline: outlineDark,
      outlineVariant: outlineVariantDark,
      inverseSurface: Color(0xFFE6EEEB),
      onInverseSurface: Color(0xFF1E2422),
    ),
    scaffoldBackgroundColor: backgroundDark,
    textTheme: GoogleFonts.nunitoSansTextTheme(
      const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          color: Color(0xFFE6EEEB),
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: Color(0xFFE6EEEB),
        ),
        displaySmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: Color(0xFFE6EEEB),
        ),
        headlineLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: Color(0xFFE6EEEB),
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Color(0xFFE6EEEB),
        ),
        headlineSmall: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Color(0xFFE6EEEB),
        ),
        titleLarge: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: Color(0xFFE6EEEB),
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Color(0xFFE6EEEB),
        ),
        titleSmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFFE6EEEB),
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: Color(0xFFE6EEEB),
        ),
        bodyMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: Color(0xFFB0BDB9),
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: Color(0xFFB0BDB9),
        ),
        labelLarge: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Color(0xFFE6EEEB),
        ),
        labelMedium: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFFB0BDB9),
        ),
        labelSmall: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Color(0xFFB0BDB9),
        ),
      ),
    ),
    appBarTheme: AppBarThemeData(
      backgroundColor: backgroundDark,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: GoogleFonts.nunitoSans(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: const Color(0xFFE6EEEB),
      ),
      iconTheme: const IconThemeData(color: Color(0xFFE6EEEB)),
    ),
    cardTheme: CardThemeData(
      color: surfaceDark,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: outlineVariantDark, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surfaceVariantDark,
      selectedColor: const Color(0xFF1A5A50),
      labelStyle: GoogleFonts.nunitoSans(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: const Color(0xFFE6EEEB),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
      side: const BorderSide(color: outlineDark),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: primaryLight,
      foregroundColor: Colors.white,
      elevation: 4,
      shape: CircleBorder(),
    ),
    dividerTheme: const DividerThemeData(
      color: outlineVariantDark,
      thickness: 1,
      space: 1,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: surfaceDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
  );
}
