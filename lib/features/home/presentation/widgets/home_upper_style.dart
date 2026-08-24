import 'package:flutter/material.dart';

/// Visual tokens for Home's approved premium upper-half concept.
///
/// Kept feature-local during Phase 1 so lower Home content and every other
/// screen retain their current V2.1 presentation until their own milestone.
abstract final class HomeUpperStyle {
  static const Color navy = Color(0xFF172033);
  static const Color primaryBlue = Color(0xFF3157D5);
  static const Color deepBlue = Color(0xFF233E9A);
  static const Color orange = Color(0xFFFF9F2F);
  static const Color background = Color(0xFFF6F7FB);
  static const Color card = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF171A24);
  static const Color textSecondary = Color(0xFF707583);
  static const Color border = Color(0xFFE7E9EF);
  static const Color radarCyan = Color(0xFF6CD7FF);

  static const double storageRadius = 24;
  static const double heroRadius = 22;
}
