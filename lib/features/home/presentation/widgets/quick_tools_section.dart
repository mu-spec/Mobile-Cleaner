import 'package:flutter/material.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';
import 'package:mobile_cleaner/app/theme/app_tokens.dart';
import 'package:mobile_cleaner/core/ui/app_visuals.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/home_section.dart';

/// Four compact shortcuts to existing features.
///
/// Normal phone widths use a 2×2 tile layout. Narrow screens and large system
/// text switch to compact full-width rows so labels can grow without clipping
/// or overflowing. The destinations themselves are supplied by Home and are
/// unchanged.
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
            final bool useGrid =
                constraints.maxWidth >= 320 && textScale <= 1.3;
            final double itemWidth = useGrid
                ? (constraints.maxWidth - HomeMetrics.rowGap) / 2
                : constraints.maxWidth;

            return Wrap(
              spacing: HomeMetrics.rowGap,
              runSpacing: HomeMetrics.rowGap,
              children: <Widget>[
                for (final _QuickToolData tool in tools)
                  SizedBox(
                    width: itemWidth,
                    child: _QuickToolTile(
                      data: tool,
                      horizontal: !useGrid,
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
  const _QuickToolTile({required this.data, required this.horizontal});

  final _QuickToolData data;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final Widget copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          data.title,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          data.subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            height: 1.3,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: data.key,
        onTap: data.onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: horizontal ? 72 : 122,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: horizontal
                ? Row(
                    children: <Widget>[
                      AppIconContainer(
                        icon: data.icon,
                        accent: data.tint,
                        size: 40,
                        iconSize: 20,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: copy),
                      const SizedBox(width: AppSpacing.xs),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      AppIconContainer(
                        icon: data.icon,
                        accent: data.tint,
                        size: 36,
                        iconSize: 19,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      copy,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
