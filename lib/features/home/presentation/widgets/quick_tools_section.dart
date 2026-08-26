import 'package:flutter/material.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';
import 'package:mobile_cleaner/app/theme/app_tokens.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Four equal Phosphor-Duotone shortcut tiles in one compact premium row.
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
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    final List<_QuickToolData> tools = <_QuickToolData>[
      _QuickToolData(
        key: const Key('quick_photos'),
        icon: PhosphorIconsDuotone.image,
        tint: AppColors.photoAccent,
        surface: AppColors.softPhoto,
        title: 'Photos',
        subtitle: 'Duplicates,\nscreenshots,\nimages',
        onTap: onPhotos,
      ),
      _QuickToolData(
        key: const Key('quick_files'),
        icon: PhosphorIconsDuotone.folder,
        tint: AppColors.actionBlue,
        surface: AppColors.softBlue,
        title: 'Large Files',
        subtitle: 'Find your\nbiggest space\nusers',
        onTap: onFiles,
      ),
      _QuickToolData(
        key: const Key('quick_apps'),
        icon: PhosphorIconsDuotone.squaresFour,
        tint: AppColors.indigoAccent,
        surface: AppColors.softIndigo,
        title: 'Apps',
        subtitle: 'Check installed\napp sizes',
        onTap: onApps,
      ),
      _QuickToolData(
        key: const Key('quick_permissions'),
        icon: PhosphorIconsDuotone.lock,
        tint: AppColors.cleanupOrange,
        surface: AppColors.softOrange,
        title: 'Storage Access',
        subtitle: 'Review or update\npermissions',
        onTap: onPermissions,
      ),
    ];

    return Column(
      key: const Key('quick_tools_section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Header
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xxs,
            right: AppSpacing.xxs,
            bottom: AppSpacing.xs,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Semantics(
                header: true,
                child: Text(
                  'Quick Tools',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? theme.colorScheme.onSurface
                        : AppColors.navy,
                  ),
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  'Review before removing',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Four-across card
        Card(
          elevation: isDark ? 0 : 1,
          shadowColor: AppColors.navy.withValues(alpha: 0.045),
          color: isDark
              ? theme.colorScheme.surfaceContainerHigh
              : AppColors.card,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : AppColors.border,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxs,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (int i = 0; i < tools.length; i++) ...<Widget>[
                  if (i > 0) const SizedBox(width: AppSpacing.xxs),
                  Expanded(
                    child: _QuickToolShortcut(
                      data: tools[i],
                      isDark: isDark,
                    ),
                  ),
                ],
              ],
            ),
          ),
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

class _QuickToolShortcut extends StatelessWidget {
  const _QuickToolShortcut({required this.data, required this.isDark});

  final _QuickToolData data;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Semantics(
      button: true,
      label: data.title,
      child: InkWell(
        key: data.key,
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(AppRadius.tile),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xxs,
            vertical: AppSpacing.xxs,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Phosphor Duotone icon container
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isDark
                      ? data.tint.withValues(alpha: 0.22)
                      : data.surface,
                  borderRadius: BorderRadius.circular(AppRadius.tile),
                ),
                child: Center(
                  child: PhosphorIcon(
                    data.icon,
                    size: 21,
                    color: data.tint,
                    duotoneSecondaryColor: data.tint.withValues(alpha: 0.55),
                    duotoneSecondaryOpacity: 0.45,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                data.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                  letterSpacing: -0.1,
                  color: isDark
                      ? theme.colorScheme.onSurface
                      : AppColors.navy,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                data.subtitle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
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
