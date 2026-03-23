import 'package:flutter/material.dart';

// ─────────────────────────────────────────
// Signtone Brand Colors
// ─────────────────────────────────────────
class AppColors {
  AppColors._();

  static const Color primary       = Color(0xFF6C63FF); // purple
  static const Color primaryDark   = Color(0xFF4B44CC);
  static const Color primaryLight  = Color(0xFF9C95FF);

  static const Color accent        = Color(0xFF00D4AA); // teal confirm
  static const Color accentDark    = Color(0xFF00A882);

  static const Color background    = Color(0xFFF8F7FF);
  static const Color surface       = Color(0xFFFFFFFF);
  static const Color surfaceDark   = Color(0xFFF0EFF9);

  static const Color textPrimary   = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF6B6B8A);
  static const Color textHint      = Color(0xFFAAAAAA);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  static const Color error         = Color(0xFFE53935);
  static const Color success       = Color(0xFF43A047);
  static const Color warning       = Color(0xFFFB8C00);

  static const Color divider       = Color(0xFFE8E7F0);
  static const Color cardShadow    = Color(0x1A6C63FF);

  // Listener screen pulse animation color
  static const Color listenerPulse = Color(0x336C63FF);
}

// ─────────────────────────────────────────
// Text Styles
// ─────────────────────────────────────────
class AppTextStyles {
  AppTextStyles._();

  static const TextStyle displayLarge = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
    letterSpacing: 1.5,
  );

  static const TextStyle displaySmall = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
    letterSpacing: 0.5,
  );

  static const TextStyle headline = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  static const TextStyle bodySecondary = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    color: AppColors.textSecondary,
    height: 1.5,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.normal,
    color: AppColors.textSecondary,
    letterSpacing: 0.3,
  );

  static const TextStyle label = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    letterSpacing: 0.5,
  );

  static const TextStyle tagline = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    color: AppColors.textOnPrimary,
    letterSpacing: 1.2,
  );

  static const TextStyle button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textOnPrimary,
    letterSpacing: 0.8,
  );
}

// ─────────────────────────────────────────
// Spacing & Radius
// ─────────────────────────────────────────
class AppSpacing {
  AppSpacing._();

  static const double xs  = 4.0;
  static const double sm  = 8.0;
  static const double md  = 16.0;
  static const double lg  = 24.0;
  static const double xl  = 32.0;
  static const double xxl = 48.0;
}

class AppRadius {
  AppRadius._();

  static const double sm   = 8.0;
  static const double md   = 12.0;
  static const double lg   = 20.0;
  static const double xl   = 32.0;
  static const double full = 999.0;
}

// ─────────────────────────────────────────
// Shadows
// ─────────────────────────────────────────
class AppShadows {
  AppShadows._();

  static const List<BoxShadow> card = [
    BoxShadow(
      color: AppColors.cardShadow,
      blurRadius: 16,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> button = [
    BoxShadow(
      color: AppColors.cardShadow,
      blurRadius: 12,
      offset: Offset(0, 4),
    ),
  ];
}

// ─────────────────────────────────────────
// ThemeData
// ─────────────────────────────────────────
class AppTheme {
  AppTheme._();

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          secondary: AppColors.accent,
          surface: AppColors.surface,
          error: AppColors.error,
        ),
        scaffoldBackgroundColor: AppColors.background,
        fontFamily: 'SF Pro Display', // falls back to system font on device

        // AppBar
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: AppTextStyles.headline,
        ),

        // ElevatedButton
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textOnPrimary,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            textStyle: AppTextStyles.button,
            elevation: 0,
          ),
        ),

        // OutlinedButton
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            minimumSize: const Size(double.infinity, 52),
            side: const BorderSide(color: AppColors.primary, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            textStyle: AppTextStyles.button.copyWith(
              color: AppColors.primary,
            ),
          ),
        ),

        // Card
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
        ),

        // Divider
        dividerTheme: const DividerThemeData(
          color: AppColors.divider,
          thickness: 1,
          space: 1,
        ),

        // SnackBar
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.textPrimary,
          contentTextStyle: AppTextStyles.body.copyWith(
            color: AppColors.textOnPrimary,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
}
