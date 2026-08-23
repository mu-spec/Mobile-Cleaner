import 'package:flutter/material.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';
import 'package:mobile_cleaner/app/theme/app_tokens.dart';
import 'package:mobile_cleaner/core/ui/app_visuals.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/home_section.dart';

/// Four compact shortcuts to existing features.
///
/// A normal phone shows all four in one row. Narrow layouts move to two
/// columns, while large system text uses full-width rows so no label clips.
/// Destinations are supplied by Home and remain unchanged.
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
        tint: const Color(0xFFF0643A),
        title: 'Photos',
        subtitle: 'Duplicates & screenshots',
        onTap: onPhotos,
      ),
      _QuickToolData(
        key: const Key('quick_files'),
        icon: Icons.folder_rounded,
        tint: AppColors.primary,
        title: 'Large Files',
        subtitle: 'Biggest space users',
        onTap: onFiles,
      ),
      _QuickToolData(
        key: const Key('quick_apps'),
        icon: Icons.apps_rounded,
        tint: const Color(0xFF4F5FD5),
        title: 'Apps',
        subtitle: 'Installed app sizes',
        onTap: onApps,
      ),
      _QuickToolData(
        key: const Key('quick_permissions'),
        icon: Icons.folder_shared_rounded,
        tint: AppColors.accentOrange,
        title: 'Storage Access',
        subtitle: 'Review permissions',
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
            final _QuickToolLayout layout;
            final int columns;
            if (constraints.maxWidth >= 360 && textScale <= 1.2) {
              layout = _QuickToolLayout.fourAcross;
              columns = 4;
            } else if (constraints.maxWidth >= 280 && textScale <= 1.35) {
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
                    child: _QuickToolTile(data: tool, layout: layout),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

enum _QuickToolLayout { fourAcross, grid, row }

class _QuickToolData {
  const _QuickToolData({
    required this.key,
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Key key;
  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _QuickToolTile extends StatelessWidget {
  const _QuickToolTile({required this.data, required this.layout});

  final _QuickToolData data;
  final _QuickToolLayout layout;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool fourAcross = layout == _QuickToolLayout.fourAcross;
    final bool fullRow = layout == _QuickToolLayout.row;

    final Widget copy = Column(
      crossAxisAlignment: fourAcross
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          data.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: fourAcross ? TextAlign.center : TextAlign.start,
          style: (fourAcross
                  ? theme.textTheme.labelMedium
                  : theme.textTheme.bodySmall)
              ?.copyWith(fontWeight: FontWeight.w700, height: 1.15),
        ),
        if (!fourAcross) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            data.subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 10,
              height: 1.2,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: data.key,
        onTap: data.onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: fourAcross ? 92 : 72),
          child: Padding(
            padding: EdgeInsets.all(fourAcross ? AppSpacing.xs : 10),
            child: fourAcross
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      AppIconContainer(
                        icon: data.icon,
                        accent: data.tint,
                        size: 32,
                        iconSize: 17,
                      ),
                      const SizedBox(height: 6),
                      copy,
                    ],
                  )
                : Row(
                    children: <Widget>[
                      AppIconContainer(
                        icon: data.icon,
                        accent: data.tint,
                        size: 34,
                        iconSize: 18,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(child: copy),
                      if (fullRow) ...<Widget>[
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
