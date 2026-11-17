import 'package:deltanium_app/config/brand.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Legacy AppColors kept for older widgets; mapped to Brand.
class AppColors {
  static const Color primary = Brand.sand;
  static const Color black = Brand.ink;
  static const Color darkGrey = Brand.inkSoft;
  static const Color mediumGrey = Brand.muted;
  static const Color lightGrey = Brand.muted;
  static const Color extraLightGrey = Brand.line;
  static const Color white = Brand.text;
  static const Color error = Brand.danger;
  static const Color success = Brand.moss;
}

class DeltaniumTheme {
  // Mapped to marketing Brand so existing screens pick up the new look.
  static const Color primaryBrown = Brand.mossDeep;
  static const Color primaryTan = Brand.sand;
  static const Color accentGreen = Brand.moss;
  static const Color accentRust = Brand.danger;

  static const Color backgroundLight = Color(0xFFF3EFE6);
  static const Color backgroundDark = Brand.ink;
  static const Color surfaceLight = Color(0xFFE8E2D6);
  static const Color surfaceDark = Brand.panel;

  static const Color lightTextPrimaryColor = Brand.ink;
  static const Color lightTextSecondaryColor = Color(0xFF4A5A50);
  static const Color darkTextPrimaryColor = Brand.text;
  static const Color darkTextSecondaryColor = Brand.muted;
  static const Color lightTextDisabledColor = Color(0xFF9AAB9F);
  static const Color darkTextDisabledColor = Color(0xFF6A7A70);

  static const Color errorColor = Brand.danger;
  static const Color successColor = Brand.moss;
  static const Color warningColor = Brand.sand;
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Brand.ink;

  static const Color tabSelectedLight = primaryBrown;
  static const Color tabUnselectedLight = lightTextSecondaryColor;
  static const Color tabSelectedDark = primaryTan;
  static const Color tabUnselectedDark = darkTextSecondaryColor;
  static const Color tabIndicatorLight = primaryBrown;
  static const Color tabIndicatorDark = primaryTan;

  static const Color dividerLight = Color(0xFFD8CFC0);
  static const Color dividerDark = Color(0xFF2A3830);
  static const Color lightDividerColor = dividerLight;
  static const Color darkDividerColor = dividerDark;

  static const Color loadingOverlayLight = Color(0x80F3EFE6);
  static const Color loadingOverlayDark = Color(0x800C1210);
  static const Color progressIndicatorLight = primaryBrown;
  static const Color progressIndicatorDark = primaryTan;

  static const Color buttonLight = primaryBrown;
  static const Color buttonDark = primaryTan;
  static const Color linkLight = primaryBrown;
  static const Color linkDark = primaryTan;
  static const Color iconLight = primaryBrown;
  static const Color iconDark = primaryTan;

  static const double spacingXSmall = 4.0;
  static const double spacingSmall = 8.0;
  static const double spacingMedium = 16.0;
  static const double spacingLarge = 24.0;
  static const double spacingXLarge = 32.0;

  static const double borderRadiusSmall = 4.0;
  static const double borderRadiusMedium = 8.0;
  static const double borderRadiusLarge = 12.0;
  static const double borderRadiusXLarge = 16.0;
  static const double borderRadiusCircular = 999.0;

  static const double fontSizeSmall = 12.0;
  static const double fontSizeRegular = 14.0;
  static const double fontSizeMedium = 16.0;
  static const double fontSizeLarge = 18.0;
  static const double fontSizeXLarge = 24.0;

  static TextStyle get headlineLight => GoogleFonts.syne(
        fontSize: fontSizeXLarge,
        fontWeight: FontWeight.w800,
        color: lightTextPrimaryColor,
      );

  static TextStyle get headlineDark => GoogleFonts.syne(
        fontSize: fontSizeXLarge,
        fontWeight: FontWeight.w800,
        color: darkTextPrimaryColor,
      );

  static TextStyle get bodyLight => GoogleFonts.manrope(
        fontSize: fontSizeRegular,
        color: lightTextPrimaryColor,
      );

  static TextStyle get bodyDark => GoogleFonts.manrope(
        fontSize: fontSizeRegular,
        color: darkTextPrimaryColor,
      );

  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        primaryColor: primaryBrown,
        scaffoldBackgroundColor: backgroundLight,
        colorScheme: const ColorScheme.light(
          primary: primaryBrown,
          secondary: accentGreen,
          surface: surfaceLight,
          error: errorColor,
          onPrimary: white,
          onSecondary: white,
          onSurface: lightTextPrimaryColor,
          onError: white,
        ),
        textTheme: GoogleFonts.manropeTextTheme().apply(
          bodyColor: lightTextPrimaryColor,
          displayColor: lightTextPrimaryColor,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: backgroundLight,
          foregroundColor: lightTextPrimaryColor,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: GoogleFonts.syne(
            fontSize: fontSizeLarge,
            fontWeight: FontWeight.w700,
            color: lightTextPrimaryColor,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: buttonLight,
            foregroundColor: white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Brand.radius),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: Brand.sand,
            foregroundColor: Brand.ink,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Brand.radius),
            ),
          ),
        ),
        cardTheme: CardThemeData(
          color: white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Brand.radius + 4),
            side: const BorderSide(color: dividerLight),
          ),
        ),
        dividerTheme: const DividerThemeData(color: dividerLight, thickness: 1),
        tabBarTheme: TabBarThemeData(
          labelColor: tabSelectedLight,
          unselectedLabelColor: tabUnselectedLight,
          indicatorColor: tabIndicatorLight,
          labelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700),
          unselectedLabelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w500),
        ),
      );

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        primaryColor: primaryTan,
        scaffoldBackgroundColor: backgroundDark,
        canvasColor: backgroundDark,
        cardColor: surfaceDark,
        dividerColor: dividerDark,
        colorScheme: const ColorScheme.dark(
          primary: primaryTan,
          secondary: accentGreen,
          surface: surfaceDark,
          error: errorColor,
          onPrimary: backgroundDark,
          onSecondary: backgroundDark,
          onSurface: darkTextPrimaryColor,
          onError: white,
        ),
        textTheme: GoogleFonts.manropeTextTheme(ThemeData.dark().textTheme).apply(
          bodyColor: darkTextPrimaryColor,
          displayColor: darkTextPrimaryColor,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: backgroundDark,
          foregroundColor: darkTextPrimaryColor,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: GoogleFonts.syne(
            fontSize: fontSizeLarge,
            fontWeight: FontWeight.w700,
            color: darkTextPrimaryColor,
          ),
          iconTheme: const IconThemeData(color: darkTextPrimaryColor),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: buttonDark,
            foregroundColor: backgroundDark,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Brand.radius),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: Brand.sand,
            foregroundColor: Brand.ink,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Brand.radius),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Brand.text,
            side: const BorderSide(color: Brand.line),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Brand.radius),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Brand.inkSoft,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Brand.radius),
            borderSide: const BorderSide(color: Brand.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Brand.radius),
            borderSide: const BorderSide(color: Brand.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(Brand.radius),
            borderSide: const BorderSide(color: Brand.sand, width: 1.4),
          ),
        ),
        cardTheme: CardThemeData(
          color: surfaceDark,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Brand.radius + 4),
            side: const BorderSide(color: dividerDark),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: surfaceDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Brand.radius + 4),
          ),
        ),
        dividerTheme: const DividerThemeData(color: dividerDark, thickness: 1),
        progressIndicatorTheme: const ProgressIndicatorThemeData(color: progressIndicatorDark),
        tabBarTheme: TabBarThemeData(
          labelColor: tabSelectedDark,
          unselectedLabelColor: tabUnselectedDark,
          indicatorColor: tabIndicatorDark,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: dividerDark,
          labelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 15),
          unselectedLabelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w500, fontSize: 15),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: Brand.inkSoft,
          selectedColor: Brand.sand.withValues(alpha: 0.2),
          labelStyle: GoogleFonts.manrope(color: Brand.text, fontSize: 12),
          side: const BorderSide(color: Brand.line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Brand.radius)),
        ),
      );
}
