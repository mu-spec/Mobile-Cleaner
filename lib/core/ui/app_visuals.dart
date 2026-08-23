import 'package:flutter/material.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';
import 'package:mobile_cleaner/app/theme/app_tokens.dart';

/// A consistent section heading for feature screens.
///
/// On narrow layouts or at larger text scales the trailing note moves below
/// the title instead of competing for horizontal space.
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    required this.title,
    this.caption,
    this.trailing,
    super.key,
  });

  final String title;
  final String? caption;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;
    final double textScale = MediaQuery.textScalerOf(context).scale(1);

    final Widget heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: isDark ? colors.onSurface : AppColors.navy,
            ),
          ),
        ),
        if (caption != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            caption!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );

    Widget trailingLabel() => Text(
      trailing!,
      style: theme.textTheme.labelSmall?.copyWith(
        color: colors.onSurfaceVariant,
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.xxs,
        bottom: AppSpacing.xs,
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool stack =
              !constraints.hasBoundedWidth ||
              textScale > 1.3 ||
              constraints.maxWidth < 320;

          if (trailing == null) {
            return heading;
          }
          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                heading,
                const SizedBox(height: AppSpacing.xxs),
                trailingLabel(),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(child: heading),
              const SizedBox(width: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: trailingLabel(),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A small rounded icon surface shared by cards, rows, and tool shortcuts.
class AppIconContainer extends StatelessWidget {
  const AppIconContainer({
    required this.icon,
    this.accent,
    this.backgroundColor,
    this.foregroundColor,
    this.size = 40,
    this.iconSize = 20,
    super.key,
  });

  final IconData icon;
  final Color? accent;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;
    final Color resolvedAccent = accent ?? colors.primary;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color:
            backgroundColor ??
            resolvedAccent.withValues(alpha: isDark ? 0.22 : 0.12),
        borderRadius: BorderRadius.circular(AppRadius.tile),
      ),
      child: Icon(
        icon,
        size: iconSize,
        color: foregroundColor ?? resolvedAccent,
      ),
    );
  }
}
