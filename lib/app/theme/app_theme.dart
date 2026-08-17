import 'package:flutter/material.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';

abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final ColorScheme colors = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    );
    final bool isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colors,
      scaffoldBackgroundColor: isDark
          ? AppColors.darkBackground
          : AppColors.lightBackground,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: colors.onSurface,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
            borderRadius: BorderRadius.circular(16),
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
      textTheme: ThemeData(brightness: brightness).textTheme.copyWith(
        headlineSmall: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
        titleLarge: const TextStyle(fontWeight: FontWeight.w700),
        bodyLarge: const TextStyle(height: 1.45),
      ),
    );
  }
}
