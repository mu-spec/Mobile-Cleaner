import 'package:flutter/material.dart';

/// Mobile Cleaner's controlled premium colour vocabulary.
///
/// Deep blue owns major brand moments; bright blue is interactive; orange is
/// reserved for cleanup/recoverable-space emphasis. Green means success and
/// red means a genuinely destructive action. Neutral surfaces and navy text
/// keep the interface from becoming uniformly blue.
abstract final class AppColors {
  /// Major brand surfaces and signature moments.
  static const Color brandBlue = Color(0xFF1246B8);

  /// Links, selected navigation, interactive icons, and compact actions.
  static const Color actionBlue = Color(0xFF1F63E9);

  /// Strong headings and high-emphasis text on light surfaces.
  static const Color navy = Color(0xFF172033);

  /// Cleanup and recoverable-space emphasis.
  static const Color cleanupOrange = Color(0xFFFF850A);

  /// Warm low-emphasis cleanup surface.
  static const Color softOrange = Color(0xFFFFF1DF);

  /// Low-emphasis interactive/info surface.
  static const Color softBlue = Color(0xFFEEF3FF);

  /// Photos' warm surface and icon accent.
  static const Color softPhoto = Color(0xFFFFEEE8);
  static const Color photoAccent = Color(0xFFE76845);

  /// Apps' restrained indigo surface and icon accent.
  static const Color softIndigo = Color(0xFFF0F0FF);
  static const Color indigoAccent = Color(0xFF5B5FD6);

  /// Main light-mode page background.
  static const Color lightBackground = Color(0xFFF7F8FC);

  /// Light-mode card surface.
  static const Color card = Color(0xFFFFFFFF);

  /// Dark-mode page background: cool near-black, never teal.
  static const Color darkBackground = Color(0xFF0D1218);

  /// Primary and supporting text on light surfaces.
  static const Color textPrimary = Color(0xFF171B22);
  static const Color textSecondary = Color(0xFF6F7680);

  /// Hairline borders around light cards and dividers.
  static const Color border = Color(0xFFE5E8F0);

  /// Genuine success only.
  static const Color success = Color(0xFF22B573);

  /// Caution that is not destructive.
  static const Color warning = Color(0xFFF59E0B);

  /// Destructive/delete/uninstall actions only.
  static const Color danger = Color(0xFFE53935);

  // Compatibility names used by the existing app while later screens adopt
  // the more explicit semantic names above.
  static const Color primary = actionBlue;
  static const Color primaryDeep = brandBlue;
  static const Color accentOrange = cleanupOrange;
}
