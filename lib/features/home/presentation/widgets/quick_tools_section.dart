import 'package:flutter/material.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';
import 'package:mobile_cleaner/app/theme/app_tokens.dart';
import 'package:mobile_cleaner/core/ui/app_visuals.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/home_section.dart';

/// Four compact shortcuts to existing features.
///
/// A normal portrait phone presents one neutral bar with all four tools.
/// Narrow screens fall back to two columns, and large accessibility text uses
/// full-width rows so labels and touch targets remain usable.
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
        subtitle: 'Duplicates & screenshots',
        compactSubtitle: 'Review photos',
        onTap: onPhotos,
      ),
      _QuickToolData(
        key: const Key('quick_files'),
        icon: Icons.folder_rounded,
        tint: AppColors.actionBlue,
        surface: AppColors.softBlue,
        title: 'Large Files',
        subtitle: 'Biggest space users',
        compactSubtitle: 'Find big files',
        onTap: onFiles,
      ),
      _QuickToolData(
        key: const Key('quick_apps'),
        icon: Icons.apps_rounded,
        tint: AppColors.indigoAccent,
        surface: AppColors.softIndigo,
        title: 'Apps',
        subtitle: 'Installed app sizes',
        compactSubtitle: 'App sizes',
        onTap: onApps,
      ),
      _QuickToolData(
        key: const Key('quick_permissions'),
        icon: Icons.folder_shared_rounded,
        tint: AppColors.cleanupOrange,
        surface: AppColors.softOrange,
        title: 'Storage Access',
        subtitle: 'Review permissions',
        compactSubtitle: 'Permissions',
        onTap: onPermissions,
      ),
    ];

    return Column(
      key: const Key('quick_tools_section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const AppSectionHeader(
          title: 'Quick Tools',
          trailing: 'Review before removing',
        ),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            if (constraints.maxWidth >= 300 && textScale <= 1.2) {
              return _CompactToolsBar(tools: tools);
            }

            final bool useGrid =
                constraints.maxWidth >= 280 && textScale <= 1.35;
            final int columns = useGrid ? 2 : 1;
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
                    child: _AdaptiveQuickToolTile(
                      data: tool,
                      showChevron: !useGrid,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _QuickToolData {
  const _QuickToolData({
    required this.key,
    required this.icon,
    required this.tint,
    required this.surface,
    required this.title,
    required this.subtitle,
    required this.compactSubtitle,
    required this.onTap,
  });

  final Key key;
  final IconData icon;
  final Color tint;
  final Color surface;
  final String title;
  final String subtitle;
  final String compactSubtitle;
  final VoidCallback onTap;
}

/// One white surface instead of four prominent cards.
class _CompactToolsBar extends StatelessWidget {
  const _CompactToolsBar({required this.tools});

  final List<_QuickToolData> tools;

  @override
  Widget build(BuildContext context) {
    final Color divider = Theme.of(context).colorScheme.outlineVariant;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int index = 0; index < tools.length; index++) ...<Widget>[
            if (index > 0)
              Container(
                width: 1,
                height: 72,
                margin: const EdgeInsets.only(top: 13),
                color: divider,
              ),
            Expanded(child: _CompactQuickTool(data: tools[index])),
          ],
        ],
      ),
    );
  }
}

class _CompactQuickTool extends StatelessWidget {
  const _CompactQuickTool({required this.data});

  final _QuickToolData data;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return InkWell(
      key: data.key,
      onTap: data.onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 98),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppIconContainer(
                icon: data.icon,
                accent: data.tint,
                backgroundColor: isDark
                    ? data.tint.withValues(alpha: 0.22)
                    : data.surface,
                size: 30,
                iconSize: 16,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                data.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                  color: isDark ? theme.colorScheme.onSurface : AppColors.navy,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                data.compactSubtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 8.5,
                  height: 1.1,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdaptiveQuickToolTile extends StatelessWidget {
  const _AdaptiveQuickToolTile({
    required this.data,
    required this.showChevron,
  });

  final _QuickToolData data;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: data.key,
        onTap: data.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 68),
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
                  size: 34,
                  iconSize: 18,
                ),
                const SizedBox(width: AppSpacing.xs),
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
                          fontWeight: FontWeight.w700,
                          height: 1.15,
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
                          fontSize: 10,
                          height: 1.15,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (showChevron) ...<Widget>[
                  const SizedBox(width: AppSpacing.xxs),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
