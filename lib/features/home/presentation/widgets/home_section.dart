import 'package:flutter/material.dart';
import 'package:mobile_cleaner/app/theme/app_tokens.dart';

/// Shared spacing and sizing for the Home screen.
///
/// Held in one place so the screen has a single visual rhythm rather than
/// per-widget guesses. Every gap on Home is one of these values, and each
/// value sits on the app-wide [AppSpacing] scale.
abstract final class HomeMetrics {
  /// Gap between a section heading and its content.
  static const double headingGap = AppSpacing.sm;

  /// Gap between two rows inside one card.
  static const double rowGap = AppSpacing.sm;

  /// Gap between major sections. Deliberately compact: the screen should
  /// show useful content without excessive scrolling.
  static const double sectionGap = AppSpacing.lg;

  /// Padding inside a card.
  static const EdgeInsets cardPadding = AppSpacing.card;

  /// Leading icon size for list rows.
  static const double rowIconSize = 20;

  /// Size of the tinted square behind a row icon.
  static const double iconTileSize = 40;

  /// Minimum height of a tappable row, comfortably above the 48dp guideline.
  static const double rowMinHeight = 56;
}

/// A section heading, optionally with a caption underneath and a small
/// trailing label on the right.
///
/// One widget so every section on Home shares the same weight, size, and
/// spacing — the thing that most makes a screen read as designed rather than
/// assembled.
class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader({
    required this.title,
    this.caption,
    this.trailing,
    super.key,
  });

  final String title;
  final String? caption;

  /// Small right-aligned metadata, e.g. "Review before removing".
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: HomeMetrics.headingGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (caption != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    caption!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: AppSpacing.xs),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                trailing!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A tinted square holding a section or tool icon.
class HomeIconTile extends StatelessWidget {
  const HomeIconTile({
    required this.icon,
    this.background,
    this.foreground,
    super.key,
  });

  final IconData icon;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Container(
      width: HomeMetrics.iconTileSize,
      height: HomeMetrics.iconTileSize,
      decoration: BoxDecoration(
        color: background ?? colors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.tile),
      ),
      child: Icon(
        icon,
        size: HomeMetrics.rowIconSize,
        color: foreground ?? colors.primary,
      ),
    );
  }
}
