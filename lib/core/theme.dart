import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Modern Design System for Study Pulse
/// Dark theme with soft purple and cyan accents
class AppTheme {
  // ============================================================================
  // COLORS
  // ============================================================================

  // Backgrounds
  static const Color bgDeepDark = Color(0xFF0D0F14);
  static const Color bgCard = Color(0xFF1A1D24);
  static const Color bgCardLight = Color(0xFF232830);

  // Accents
  static const Color accentPrimary = Color(0xFFB8A5FF); // Soft purple
  static const Color accentPrimaryDark = Color(0xFF9D7FF0);
  static const Color accentSecondary = Color(0xFF5FD3F3); // Cyan
  static const Color accentSecondaryDark = Color(0xFF2FC4E8);

  // Text
  static const Color textPrimary = Color(0xFFFAFAFA);
  static const Color textSecondary = Color(0xFFB0B4C1);
  static const Color textTertiary = Color(0xFF8A8E99);

  // Status colors
  static const Color statusSuccess = Color(0xFF6DD5A8);
  static const Color statusWarning = Color(0xFFFFB366);
  static const Color statusError = Color(0xFFFF8A80);
  static const Color statusInfo = Color(0xFF5FD3F3);

  // Gradients
  static const LinearGradient gradientPrimary = LinearGradient(
    colors: [accentPrimary, accentPrimaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient gradientSecondary = LinearGradient(
    colors: [accentSecondary, accentSecondaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient gradientBackground = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF0D0F14),
      Color(0xFF131820),
      Color(0xFF1A1D24),
    ],
  );

  // ============================================================================
  // SPACING
  // ============================================================================

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  // ============================================================================
  // BORDER RADIUS
  // ============================================================================

  static const double radiusSmall = 8;
  static const double radiusMedium = 12;
  static const double radiusLarge = 20;
  static const double radiusXLarge = 24;

  // ============================================================================
  // BUILD THEME
  // ============================================================================

  static ThemeData buildTheme() {
    final baseTextTheme = GoogleFonts.interTextTheme();

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgDeepDark,
      canvasColor: bgCard,

      // ====== TEXT / TYPOGRAPHY ======
      textTheme: baseTextTheme.copyWith(
        // Display styles: used for headings
        displayLarge: baseTextTheme.displayLarge?.copyWith(
          color: textPrimary,
          fontSize: 36,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        displayMedium: baseTextTheme.displayMedium?.copyWith(
          color: textPrimary,
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        displaySmall: baseTextTheme.displaySmall?.copyWith(
          color: textPrimary,
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),

        // Headline styles
        headlineLarge: baseTextTheme.headlineLarge?.copyWith(
          color: textPrimary,
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        headlineMedium: baseTextTheme.headlineMedium?.copyWith(
          color: textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        headlineSmall: baseTextTheme.headlineSmall?.copyWith(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),

        // Title styles
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
        titleMedium: baseTextTheme.titleMedium?.copyWith(
          color: textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
        titleSmall: baseTextTheme.titleSmall?.copyWith(
          color: textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),

        // Body styles
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(
          color: textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.3,
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          color: textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.2,
        ),
        bodySmall: baseTextTheme.bodySmall?.copyWith(
          color: textTertiary,
          fontSize: 12,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.4,
        ),

        // Label styles
        labelLarge: baseTextTheme.labelLarge?.copyWith(
          color: textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        labelMedium: baseTextTheme.labelMedium?.copyWith(
          color: textPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
        labelSmall: baseTextTheme.labelSmall?.copyWith(
          color: textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
        ),
      ),

      // ====== COLORS ======
      colorScheme: ColorScheme.dark(
        brightness: Brightness.dark,
        primary: accentPrimary,
        onPrimary: bgDeepDark,
        primaryContainer: accentPrimaryDark,
        onPrimaryContainer: textPrimary,
        secondary: accentSecondary,
        onSecondary: bgDeepDark,
        secondaryContainer: accentSecondaryDark,
        onSecondaryContainer: textPrimary,
        surface: bgCard,
        onSurface: textPrimary,
        surfaceContainerHighest: bgCardLight,
        error: statusError,
        onError: bgDeepDark,
      ),

      // ====== BUTTONS ======
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accentPrimary,
          foregroundColor: bgDeepDark,
          padding: const EdgeInsets.symmetric(
            horizontal: lg,
            vertical: lg,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLarge),
          ),
          elevation: 0,
          textStyle: baseTextTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: accentSecondary,
          padding: const EdgeInsets.symmetric(
            horizontal: lg,
            vertical: lg,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLarge),
          ),
          side: const BorderSide(
            color: accentSecondary,
            width: 1.5,
          ),
          textStyle: baseTextTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentSecondary,
          padding: const EdgeInsets.symmetric(
            horizontal: md,
            vertical: md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
          ),
          textStyle: baseTextTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // ====== INPUT FIELDS ======
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgCard,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: lg,
          vertical: lg,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          borderSide: const BorderSide(
            color: bgCardLight,
            width: 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          borderSide: BorderSide(
            color: textTertiary.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          borderSide: const BorderSide(
            color: accentSecondary,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          borderSide: const BorderSide(
            color: statusError,
            width: 1,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          borderSide: const BorderSide(
            color: statusError,
            width: 2,
          ),
        ),
        hintStyle: TextStyle(
          color: textTertiary,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        labelStyle: TextStyle(
          color: textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        errorStyle: TextStyle(
          color: statusError,
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      ),

      // ====== CARDS ======
      cardTheme: CardThemeData(
        color: bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
          side: BorderSide(
            color: bgCardLight,
            width: 1,
          ),
        ),
      ),

      // ====== APP BAR ======
      appBarTheme: AppBarThemeData(
        backgroundColor: bgDeepDark,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: baseTextTheme.titleLarge?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: const IconThemeData(
          color: accentSecondary,
          size: 24,
        ),
      ),

      // ====== SNACKBAR ======
      snackBarTheme: SnackBarThemeData(
        backgroundColor: bgCard,
        contentTextStyle: baseTextTheme.bodyMedium?.copyWith(
          color: textPrimary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.all(lg),
      ),

      // ====== PROGRESS INDICATORS ======
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accentSecondary,
        linearTrackColor: bgCardLight,
        circularTrackColor: bgCardLight,
      ),

      // ====== DIVIDER ======
      dividerTheme: DividerThemeData(
        color: bgCardLight,
        thickness: 1,
        space: xl,
      ),

      // ====== ICON BUTTON ======
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: accentSecondary,
          iconSize: 24,
          padding: const EdgeInsets.all(md),
        ),
      ),
    );
  }
}
