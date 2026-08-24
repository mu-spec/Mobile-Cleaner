import 'package:flutter/material.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';
import 'package:mobile_cleaner/app/theme/app_tokens.dart';
import 'package:mobile_cleaner/core/ui/app_visuals.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/home_section.dart';

/// Four compact shortcuts to existing features.
///
/// A normal portrait phone presents four independent premium tiles in one
/// row. Narrow screens use two columns, and large accessibility text uses
/// full-width rows so every label remains readable. Each tile carries just
/// an icon, a compact bold title, and a short neutral subtitle.
class QuickToolsSection extends StatelessWidget {
  const QuickToolsSection({
    required this.onPhotos,
    required this.onFiles,
    required this.onApps,
    required this.onPermissions,
    super.key,
  });

  final VoidCallback onPhotos;
  final VoidCallback onFiles;
  final VoidCallback onApps;
  final VoidCallback onPermissions;

  @override
  Widget build(BuildContext context) {
    final double textScale = MediaQuery.textScalerOf(context).scale(1);
    final List<_QuickToolData> tools = <_QuickToolData>[
      _QuickToolData(
        key: const Key('quick_photos'),
        icon: Icons.photo_library_rounded,
        tint: AppColors.photoAccent,
        surface: AppColors.softPhoto,
        title: 'Photos',
        subtitle: 'Review photos',
        onTap: onPhotos,
      ),
      _QuickToolData(
        key: const Key('quick_files'),
        icon: Icons.folder_rounded,
        tint: AppColors.actionBlue,
        surface: AppColors.softBlue,
        title: 'Large Files',
        subtitle: 'Find big files',
        onTap: onFiles,
      ),
      _QuickToolData(
        key: const Key('quick_apps'),
        icon: Icons.apps_rounded,
        tint: AppColors.indigoAccent,
        surface: AppColors.softIndigo,
        title: 'Apps',
        subtitle: 'App sizes',
        onTap: onApps,
      ),
      _QuickToolData(
        key: const Key('quick_permissions'),
        icon: Icons.folder_shared_rounded,
        tint: AppColors.cleanupOrange,
        surface: AppColors.softOrange,
        title: 'Storage',
        subtitle: 'Permissions',
        onTap: onPermissions,
      ),
    ];

    return Column(
      key: const Key('quick_tools_section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _QuickToolsHeader(),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final _QuickToolLayout layout;
            final int columns;
            if (constraints.maxWidth >= 320 && textScale <= 1.15) {
              layout = _QuickToolLayout.fourAcross;
              columns = 4;
            } else if (constraints.maxWidth >= 280 && textScale <= 1.4) {
              layout = _QuickToolLayout.grid;
              columns = 2;
            } else {
              layout = _QuickToolLayout.row;
              columns = 1;
            }

            final double itemWidth =
                (constraints.maxWidth - HomeMetrics.rowGap * (columns - 1)) /
                columns;

            return Wrap(
              spacing: HomeMetrics.rowGap,
              runSpacing: HomeMetrics.rowGap,
              children: <Widget>[
                for (final _QuickToolData tool in tools)
                  SizedBox(
                    width: itemWidth,
                    child: _PremiumQuickToolTile(data: tool, layout: layout),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _QuickToolsHeader extends StatelessWidget {
  const _QuickToolsHeader();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;
    final double textScale = MediaQuery.textScalerOf(context).scale(1);

    final Widget heading = Semantics(
      header: true,
      child: Text(
        'Quick Tools',
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: isDark ? colors.onSurface : AppColors.navy,
        ),
      ),
    );
    final Widget trailing = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        Flexible(
          child: Text(
            'Review before removing',
            softWrap: true,
            textAlign: TextAlign.end,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 2),
        Icon(
          Icons.chevron_right_rounded,
          size: 15,
          color: colors.onSurfaceVariant,
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.xxs,
        right: AppSpacing.xxs,
        bottom: AppSpacing.xs,
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          if (textScale > 1.3 || constraints.maxWidth < 320) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                heading,
                const SizedBox(height: 2),
                trailing,
              ],
            );
          }
          return Row(
            children: <Widget>[
              Expanded(child: heading),
              const SizedBox(width: AppSpacing.xs),
              // Flexible (not Expanded) keeps the note on one line when it
              // fits at normal text scale, but lets it shrink and wrap at
              // large accessibility sizes instead of overflowing.
              Flexible(child: trailing),
            ],
          );
        },
      ),
    );
  }
}

enum _QuickToolLayout { fourAcross, grid, row }

class _QuickToolData {
  const _QuickToolData({
    required this.key,
    required this.icon,
    required this.tint,
    required this.surface,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Key key;
  final IconData icon;
  final Color tint;
  final Color surface;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _PremiumQuickToolTile extends StatelessWidget {
  const _PremiumQuickToolTile({required this.data, required this.layout});

  final _QuickToolData data;
  final _QuickToolLayout layout;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final bool horizontal = layout == _QuickToolLayout.row;
    final bool fourAcross = layout == _QuickToolLayout.fourAcross;

    return Card(
      elevation: isDark ? 0 : 1,
      shadowColor: AppColors.navy.withValues(alpha: 0.045),
      color: isDark ? theme.colorScheme.surfaceContainerHigh : AppColors.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : AppColors.border,
        ),
      ),
      child: InkWell(
        key: data.key,
        onTap: data.onTap,
        child: horizontal
            ? _HorizontalToolContent(data: data)
            : _VerticalToolContent(data: data, fourAcross: fourAcross),
      ),
    );
  }
}

class _VerticalToolContent extends StatelessWidget {
  const _VerticalToolContent({
    required this.data,
    required this.fourAcross,
  });

  final _QuickToolData data;
  final bool fourAcross;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: fourAcross ? 108 : 102),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: fourAcross ? 6 : AppSpacing.xs,
          vertical: AppSpacing.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            AppIconContainer(
              icon: data.icon,
              accent: data.tint,
              backgroundColor: isDark
                  ? data.tint.withValues(alpha: 0.22)
                  : data.surface,
              size: fourAcross ? 32 : 36,
              iconSize: fourAcross ? 17 : 19,
            ),
            const SizedBox(height: 8),
            // Compact, bold title. Prefers one line; wraps to two only at
            // large accessibility text scales so it never overflows.
            Text(
              data.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium?.copyWith(
                fontSize: fourAcross ? 12 : 13,
                fontWeight: FontWeight.w700,
                height: 1.15,
                letterSpacing: -0.1,
                color: isDark ? theme.colorScheme.onSurface : AppColors.navy,
              ),
            ),
            const SizedBox(height: 3),
            // Smaller, neutral grey supporting line.
            Text(
              data.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: fourAcross ? 10.5 : 11,
                height: 1.2,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HorizontalToolContent extends StatelessWidget {
  const _HorizontalToolContent({required this.data});

  final _QuickToolData data;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Row(
          children: <Widget>[
            AppIconContainer(
              icon: data.icon,
              accent: data.tint,
              backgroundColor: isDark
                  ? data.tint.withValues(alpha: 0.22)
                  : data.surface,
              size: 38,
              iconSize: 19,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    data.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? theme.colorScheme.onSurface
                          : AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    data.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
