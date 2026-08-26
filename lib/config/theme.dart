import 'package:flutter/material.dart';

// App color palette
class AppColors {
  static const Color primary = Color(0xFF1DA1F2); // Twitter blue
  static const Color black = Color(0xFF000000);
  static const Color darkGrey = Color(0xFF14171A);
  static const Color mediumGrey = Color(0xFF657786);
  static const Color lightGrey = Color(0xFFAAB8C2);
  static const Color extraLightGrey = Color(0xFFE1E8ED);
  static const Color white = Color(0xFFFFFFFF);
  static const Color error = Color(0xFFE0245E); // Twitter red
  static const Color success = Color(0xFF17BF63); // Twitter green
}

// App text theme
class AppTextStyles {
  static const TextStyle headline1 = TextStyle(
    fontSize: 24.0,
    fontWeight: FontWeight.bold,
    color: AppColors.white,
  );
  
  static const TextStyle headline2 = TextStyle(
    fontSize: 20.0,
    fontWeight: FontWeight.bold,
    color: AppColors.white,
  );
  
  static const TextStyle headline3 = TextStyle(
    fontSize: 18.0,
    fontWeight: FontWeight.bold,
    color: AppColors.white,
  );
  
  static const TextStyle bodyText1 = TextStyle(
    fontSize: 16.0,
    color: AppColors.white,
  );
  
  static const TextStyle bodyText2 = TextStyle(
    fontSize: 14.0,
    color: AppColors.white,
  );
  
  static const TextStyle caption = TextStyle(
    fontSize: 12.0,
    color: AppColors.lightGrey,
  );
}

// App theme
final ThemeData appTheme = ThemeData(
  scaffoldBackgroundColor: AppColors.black,
  primaryColor: AppColors.primary,
  colorScheme: const ColorScheme.dark(
    primary: AppColors.primary,
    secondary: AppColors.primary,
    background: AppColors.black,
    surface: AppColors.darkGrey,
    error: AppColors.error,
  ),
  textTheme: TextTheme(
    displayLarge: AppTextStyles.headline1,
    displayMedium: AppTextStyles.headline2,
    displaySmall: AppTextStyles.headline3,
    bodyLarge: AppTextStyles.bodyText1,
    bodyMedium: AppTextStyles.bodyText2,
    bodySmall: AppTextStyles.caption,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.black,
    elevation: 0,
    centerTitle: true,
    titleTextStyle: AppTextStyles.headline2,
    iconTheme: IconThemeData(color: AppColors.primary),
  ),
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: AppColors.black,
    selectedItemColor: AppColors.primary,
    unselectedItemColor: AppColors.mediumGrey,
    showUnselectedLabels: true,
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(50),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
    ),
  ),
);

class DeltaniumTheme {
  // Primary Colors
  static const Color primaryBrown = Color(0xFF8B6B4E);  // Earthy brown
  static const Color primaryTan = Color(0xFFD2B48C);    // Tan
  static const Color accentGreen = Color(0xFF6B8E23);   // Olive green
  static const Color accentRust = Color(0xFFCD5C5C);    // Indian red

  // Background Colors
  static const Color backgroundLight = Color(0xFFF5F5DC);  // Beige
  static const Color backgroundDark = Color(0xFF2C1810);   // Dark brown
  static const Color surfaceLight = Color(0xFFEEE8AA);     // Light khaki
  static const Color surfaceDark = Color(0xFF3E2723);      // Dark brown

  // Text Colors
  static const Color lightTextPrimaryColor = Color(0xFF2C1810);    // Dark brown
  static const Color lightTextSecondaryColor = Color(0xFF5D4037);  // Brown
  static const Color darkTextPrimaryColor = Color(0xFFF5F5DC);     // Beige
  static const Color darkTextSecondaryColor = Color(0xFFD2B48C);   // Tan
  static const Color lightTextDisabledColor = Color(0xFFADA79B);   // Muted light text
  static const Color darkTextDisabledColor = Color(0xFF6D5D53);    // Muted dark text

  // Utility Colors
  static const Color errorColor = Color(0xFF8B0000);     // Dark red
  static const Color successColor = Color(0xFF556B2F);   // Dark olive green
  static const Color warningColor = Color(0xFFCD853F);   // Peru brown
  static const Color white = Colors.white;
  static const Color black = Colors.black;

  // Tab Colors
  static const Color tabSelectedLight = primaryBrown;
  static const Color tabUnselectedLight = lightTextSecondaryColor;
  static const Color tabSelectedDark = primaryTan;
  static const Color tabUnselectedDark = darkTextSecondaryColor;
  static const Color tabIndicatorLight = primaryBrown;
  static const Color tabIndicatorDark = primaryTan;

  // Divider Colors
  static const Color dividerLight = Color(0xFFD8C3A5);  // Light brown divider
  static const Color dividerDark = Color(0xFF4E342E);   // Dark brown divider
  static const Color lightDividerColor = dividerLight;   // Alias for consistency
  static const Color darkDividerColor = dividerDark;     // Alias for consistency

  // Loading State Colors
  static const Color loadingOverlayLight = Color(0x80F5F5DC);  // Semi-transparent beige
  static const Color loadingOverlayDark = Color(0x802C1810);   // Semi-transparent dark brown
  static const Color progressIndicatorLight = primaryBrown;
  static const Color progressIndicatorDark = primaryTan;

  // Interactive Element Colors
  static const Color buttonLight = primaryBrown;
  static const Color buttonDark = primaryTan;
  static const Color linkLight = primaryBrown;
  static const Color linkDark = primaryTan;
  static const Color iconLight = primaryBrown;
  static const Color iconDark = primaryTan;

  // Spacing
  static const double spacingXSmall = 4.0;
  static const double spacingSmall = 8.0;
  static const double spacingMedium = 16.0;
  static const double spacingLarge = 24.0;
  static const double spacingXLarge = 32.0;

  // Border Radius
  static const double borderRadiusSmall = 4.0;
  static const double borderRadiusMedium = 8.0;
  static const double borderRadiusLarge = 16.0;
  static const double borderRadiusXLarge = 24.0;
  static const double borderRadiusCircular = 999.0;

  // Font Sizes
  static const double fontSizeSmall = 12.0;
  static const double fontSizeRegular = 14.0;
  static const double fontSizeMedium = 16.0;
  static const double fontSizeLarge = 18.0;
  static const double fontSizeXLarge = 24.0;

  // Text Styles
  static const TextStyle headlineLight = TextStyle(
    fontSize: fontSizeXLarge,
    fontWeight: FontWeight.bold,
    color: lightTextPrimaryColor,
  );

  static const TextStyle headlineDark = TextStyle(
    fontSize: fontSizeXLarge,
    fontWeight: FontWeight.bold,
    color: darkTextPrimaryColor,
  );

  static const TextStyle bodyLight = TextStyle(
    fontSize: fontSizeRegular,
    color: lightTextPrimaryColor,
  );

  static const TextStyle bodyDark = TextStyle(
    fontSize: fontSizeRegular,
    color: darkTextPrimaryColor,
  );

  static ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    primaryColor: primaryBrown,
    scaffoldBackgroundColor: backgroundLight,
    drawerTheme: const DrawerThemeData(
      backgroundColor: white,
      scrimColor: Colors.transparent,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: white,
      indicatorColor: primaryBrown,
      labelTextStyle: MaterialStatePropertyAll(
        TextStyle(color: lightTextPrimaryColor),
      ),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: white,
      selectedIconTheme: IconThemeData(color: primaryBrown),
      unselectedIconTheme: IconThemeData(color: lightTextSecondaryColor),
      selectedLabelTextStyle: TextStyle(color: primaryBrown),
      unselectedLabelTextStyle: TextStyle(color: lightTextSecondaryColor),
    ),
    colorScheme: const ColorScheme.light(
      primary: primaryBrown,
      secondary: accentGreen,
      surface: surfaceLight,
      background: backgroundLight,
      error: errorColor,
      onPrimary: white,
      onSecondary: white,
      onSurface: lightTextPrimaryColor,
      onBackground: lightTextPrimaryColor,
      onError: white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: white,
      foregroundColor: lightTextPrimaryColor,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: fontSizeLarge,
        fontWeight: FontWeight.bold,
        color: lightTextPrimaryColor,
      ),
      iconTheme: IconThemeData(color: lightTextPrimaryColor),
    ),
    textTheme: const TextTheme(
      displayLarge: headlineLight,
      displayMedium: headlineLight,
      displaySmall: headlineLight,
      bodyLarge: bodyLight,
      bodyMedium: bodyLight,
      bodySmall: TextStyle(
        fontSize: fontSizeSmall,
        color: lightTextSecondaryColor,
      ),
    ),
    iconTheme: const IconThemeData(
      color: iconLight,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: white,
      selectedItemColor: primaryBrown,
      unselectedItemColor: lightTextSecondaryColor,
      showUnselectedLabels: true,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: buttonLight,
        foregroundColor: white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadiusCircular),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadiusMedium),
        borderSide: const BorderSide(color: primaryBrown),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadiusMedium),
        borderSide: const BorderSide(color: primaryBrown, width: 2),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: tabSelectedLight,
      unselectedLabelColor: tabUnselectedLight,
      indicatorColor: tabIndicatorLight,
    ),
    dividerTheme: const DividerThemeData(
      color: dividerLight,
      thickness: 1,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: progressIndicatorLight,
    ),
  );

  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: primaryTan,
    scaffoldBackgroundColor: backgroundDark,
    drawerTheme: const DrawerThemeData(
      backgroundColor: black,
      scrimColor: Colors.transparent,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: black,
      indicatorColor: primaryTan,
      labelTextStyle: MaterialStatePropertyAll(
        TextStyle(color: darkTextPrimaryColor),
      ),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: black,
      selectedIconTheme: IconThemeData(color: primaryTan),
      unselectedIconTheme: IconThemeData(color: darkTextSecondaryColor),
      selectedLabelTextStyle: TextStyle(color: primaryTan),
      unselectedLabelTextStyle: TextStyle(color: darkTextSecondaryColor),
    ),
    colorScheme: const ColorScheme.dark(
      primary: primaryTan,
      secondary: accentGreen,
      surface: surfaceDark,
      background: backgroundDark,
      error: errorColor,
      onPrimary: backgroundDark,
      onSecondary: backgroundDark,
      onSurface: darkTextPrimaryColor,
      onBackground: darkTextPrimaryColor,
      onError: white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: black,
      foregroundColor: darkTextPrimaryColor,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontSize: fontSizeLarge,
        fontWeight: FontWeight.bold,
        color: darkTextPrimaryColor,
      ),
      iconTheme: IconThemeData(color: darkTextPrimaryColor),
    ),
    textTheme: const TextTheme(
      displayLarge: headlineDark,
      displayMedium: headlineDark,
      displaySmall: headlineDark,
      bodyLarge: bodyDark,
      bodyMedium: bodyDark,
      bodySmall: TextStyle(
        fontSize: fontSizeSmall,
        color: darkTextSecondaryColor,
      ),
    ),
    iconTheme: const IconThemeData(
      color: iconDark,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: black,
      selectedItemColor: primaryTan,
      unselectedItemColor: darkTextSecondaryColor,
      showUnselectedLabels: true,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: buttonDark,
        foregroundColor: backgroundDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadiusCircular),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceDark,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadiusMedium),
        borderSide: const BorderSide(color: primaryTan),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadiusMedium),
        borderSide: const BorderSide(color: primaryTan, width: 2),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: tabSelectedDark,
      unselectedLabelColor: tabUnselectedDark,
      indicatorColor: tabIndicatorDark,
    ),
    dividerTheme: const DividerThemeData(
      color: dividerDark,
      thickness: 1,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: progressIndicatorDark,
    ),
  );
} 