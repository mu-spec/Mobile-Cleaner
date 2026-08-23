import 'package:flutter/material.dart';

/// The app's colour vocabulary (UI V2.1).
///
/// One blue identity with a single orange accent. Green is reserved for
/// genuine success, red for genuinely destructive actions — neither is ever
/// decorative. The previous teal identity is gone from the visual language.
abstract final class AppColors {
  /// Primary brand blue — the one colour that means "this app".
  static const Color primary = Color(0xFF1E5FE0);

  /// Deep blue used for rich surfaces such as the Smart Scan hero card.
  static const Color primaryDeep = Color(0xFF073EA7);

  /// Cleanup accent orange. An accent only — never a second brand colour.
  static const Color accentOrange = Color(0xFFFF8A00);

  /// Main light-mode page background: very light cool gray.
  static const Color lightBackground = Color(0xFFF7F9FC);

  /// Dark-mode page background: cool near-black, no teal cast.
  static const Color darkBackground = Color(0xFF0D1218);

  /// Primary text on light surfaces.
  static const Color textPrimary = Color(0xFF14191F);

  /// Secondary/supporting text on light surfaces.
  static const Color textSecondary = Color(0xFF687078);

  /// Hairline borders around light-mode cards and dividers.
  static const Color border = Color(0xFFE7EAF0);

  /// Success green — only for genuine success states.
  static const Color success = Color(0xFF16A34A);

  /// Warning amber for cautionary states.
  static const Color warning = Color(0xFFF59E0B);

  /// Danger red — only for destructive actions.
  static const Color danger = Color(0xFFDC2626);
}
