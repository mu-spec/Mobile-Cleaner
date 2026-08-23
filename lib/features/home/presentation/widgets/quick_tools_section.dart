import 'package:flutter/material.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';
import 'package:mobile_cleaner/app/theme/app_tokens.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/home_section.dart';

/// Quick Tools: four compact shortcuts, all visible at once.
///
/// A 2×2 grid of small tiles rather than four large cards — secondary tools
/// must not compete with the Smart Scan hero for visual weight. Each tile is
/// a softly tinted icon, a short title, and one tiny supporting line.
///
/// Destinations are unchanged — the same four callbacks, wired to the same
/// existing screens.
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
    return Column(
      key: const Key('quick_tools_section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const HomeSectionHeader(
          title: 'Quick Tools',
          trailing: 'Review before removing',
        ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: _QuickToolTile(
                  tileKey: const Key('quick_photos'),
                  icon: Icons.photo_library_rounded,
                  tint: const Color(0xFFFF5A3C),
                  title: 'Photos',
                  subtitle: 'Duplicates & screenshots',
                  onTap: onPhotos,
                ),
              ),
              const SizedBox(width: HomeMetrics.rowGap),
              Expanded(
                child: _QuickToolTile(
                  tileKey: const Key('quick_files'),
                  icon: Icons.folder_rounded,
                  tint: AppColors.primary,
                  title: 'Large Files',
                  subtitle: 'Biggest space users',
                  onTap: onFiles,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: HomeMetrics.rowGap),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: _QuickToolTile(
                  tileKey: const Key('quick_apps'),
                  icon: Icons.apps_rounded,
                  tint: const Color(0xFF6366F1),
                  title: 'Apps',
                  subtitle: 'Installed app sizes',
                  onTap: onApps,
                ),
              ),
              const SizedBox(width: HomeMetrics.rowGap),
              Expanded(
                child: _QuickToolTile(
                  tileKey: const Key('quick_permissions'),
                  icon: Icons.folder_shared_rounded,
                  tint: AppColors.accentOrange,
                  title: 'Storage Access',
                  subtitle: 'Review permissions',
                  onTap: onPermissions,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One compact tool tile: tinted rounded-square icon, title, tiny caption.
class _QuickToolTile extends StatelessWidget {
  const _QuickToolTile({
    required this.tileKey,
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Key tileKey;
  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: tileKey,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: HomeMetrics.rowMinHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm + 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: isDark ? 0.22 : 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.tile),
                  ),
                  child: Icon(icon, size: 19, color: tint),
                ),
                const SizedBox(height: AppSpacing.xs + 2),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    height: 1.3,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
