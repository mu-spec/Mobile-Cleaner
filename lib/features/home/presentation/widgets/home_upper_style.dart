import 'package:flutter/material.dart';

/// Visual tokens for Home's approved premium identity.
///
/// Kept feature-local so other screens retain their current presentation
/// until their own milestone. These are the compact Home palette:
/// primary/action blue, deep blue, cleanup orange, cool off-white
/// background, white cards, and near-black/slate text.
abstract final class HomeUpperStyle {
  static const Color navy = Color(0xFF0F172A);
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color deepBlue = Color(0xFF1D4ED8);
  static const Color orange = Color(0xFFFF8A00);
  static const Color background = Color(0xFFF5F7FB);
  static const Color card = Color(0xFFFFFFFF);
  static const Color softBlue = Color(0xFFEAF0FF);
  static const Color softViolet = Color(0xFFF1EDFF);
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color border = Color(0xFFE5E8F0);
  static const Color radarCyan = Color(0xFF6CD7FF);

  static const double storageRadius = 24;
  static const double heroRadius = 22;
}
