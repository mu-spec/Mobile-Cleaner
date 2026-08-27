import 'package:flutter/material.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';
import 'package:mobile_cleaner/app/theme/app_tokens.dart';

abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;

    ColorScheme colors = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    );
    if (!isDark) {
      // Pin the exact approved light tokens rather than the seed's tonal
      // approximations. The dark branch below owns its separate palette.
      colors = colors.copyWith(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        surface: AppColors.card,
        onSurface: AppColors.textPrimary,
        onSurfaceVariant: AppColors.textSecondary,
        outlineVariant: AppColors.border,
        error: AppColors.danger,
      );
    } else {
      // A purpose-built navy system keeps dark mode crisp and layered. Seed
      // generated dark colours were too gray and turned the brand blue into
      // a pale lavender, especially in Home's storage and navigation areas.
      colors = colors.copyWith(
        primary: AppColors.darkPrimary,
        onPrimary: Colors.white,
        primaryContainer: AppColors.darkPrimaryContainer,
        onPrimaryContainer: const Color(0xFFDCEAFF),
        secondary: const Color(0xFFA99AFF),
        onSecondary: const Color(0xFF17112D),
        surface: AppColors.darkSurface,
        surfaceContainerLowest: AppColors.darkBackground,
        surfaceContainerLow: const Color(0xFF0E1724),
        surfaceContainer: AppColors.darkSurface,
        surfaceContainerHigh: AppColors.darkSurfaceElevated,
        surfaceContainerHighest: const Color(0xFF1D2A3C),
        onSurface: AppColors.darkTextPrimary,
        onSurfaceVariant: AppColors.darkTextSecondary,
        outline: const Color(0xFF536178),
        outlineVariant: AppColors.darkBorder,
        error: const Color(0xFFFF6B6B),
        onError: const Color(0xFF370008),
      );
    }

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Inter',
      colorScheme: colors,
      scaffoldBackgroundColor: isDark
          ? AppColors.darkBackground
          : AppColors.lightBackground,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: colors.onSurface,
      ),
      // One card language everywhere: white (or dark surface), soft
      // hairline border, no floating shadow, no glassmorphism.
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? colors.surfaceContainerHigh : AppColors.card,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(
            color: isDark ? colors.outlineVariant : AppColors.border,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? colors.outlineVariant : AppColors.border,
      ),
      // Bottom navigation: light surface, blue selection, neutral gray rest.
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: isDark ? colors.surface : AppColors.card,
        selectedItemColor: colors.primary,
        unselectedItemColor: isDark
            ? colors.onSurfaceVariant
            : AppColors.textSecondary,
        elevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // Height only. `Size.fromHeight(56)` is `Size(infinity, 56)`, which
          // gave every FilledButton an infinite *minimum width*. Inside a Row
          // that throws "BoxConstraints forces an infinite width", because a
          // Row cannot satisfy a child demanding unbounded horizontal space.
          //
          // A button that should span the screen wraps itself in
          // `SizedBox(width: double.infinity)` at the call site, rather than
          // every button in the app being forced to stretch.
          minimumSize: const Size(0, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      // Page transitions are deliberately left at the platform default.
      //
      // Modern Flutter defaults Android to the predictive-back transition,
      // which gives the system back-gesture preview and falls back to the
      // fade-forwards animation otherwise. Naming a builder explicitly here
      // would *disable* predictive back — a downgrade, not polish.
      textTheme: ThemeData(brightness: brightness).textTheme
          .copyWith(
            headlineSmall: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
            titleLarge: const TextStyle(fontWeight: FontWeight.w700),
            titleMedium: const TextStyle(fontWeight: FontWeight.w600),
            bodyLarge: const TextStyle(height: 1.45),
          )
          .apply(fontFamily: 'Inter'),
    );
  }
}
