import 'package:flutter/widgets.dart';
import 'package:mobile_cleaner/app/theme/app_tokens.dart';

/// Shared spacing and sizing for the Home screen.
///
/// Values are aliases of the app-wide tokens so Home keeps one visual rhythm
/// without introducing a second spacing system.
abstract final class HomeMetrics {
  /// Gap between a section heading and its content.
  static const double headingGap = AppSpacing.xs;

  /// Gap between rows or tiles inside one section.
  static const double rowGap = AppSpacing.xs;

  /// Gap between major sections.
  static const double sectionGap = AppSpacing.md;

  /// Padding inside a card.
  static const EdgeInsets cardPadding = AppSpacing.card;

  /// Leading icon size for compact list rows.
  static const double rowIconSize = 20;

  /// Size of the tinted square behind a row icon.
  static const double iconTileSize = 40;

  /// Minimum height of a tappable row.
  static const double rowMinHeight = 56;
}
