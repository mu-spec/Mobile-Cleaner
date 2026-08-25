import 'package:flutter/material.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';
import 'package:mobile_cleaner/app/theme/app_tokens.dart';
import 'package:mobile_cleaner/core/ui/app_visuals.dart';

/// Four equal shortcuts inside one compact premium white container.
///
/// A single Card holds the four tools in one horizontal row. Each shortcut
/// is just a softly-tinted rounded icon and a short title — no subtitles,
/// action text, or per-tool arrows. The row always stays four-across on
/// normal phone widths; titles wrap (never overflow) and the card grows
/// vertically at large accessibility text sizes. Destinations and keys are
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
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final double textScale = MediaQuery.textScalerOf(context).scale(1);

    final List<_QuickToolData> tools = <_QuickToolData>[
      _QuickToolData(
        key: const Key('quick_photos'),
        icon: Icons.photo_outlined,
        tint: AppColors.photoAccent,
        surface: AppColors.softPhoto,
        title: 'Photos',
        onTap: onPhotos,
      ),
      _QuickToolData(
        key: const Key('quick_files'),
        icon: Icons.folder_outlined,
        tint: AppColors.actionBlue,
        surface: AppColors.softBlue,
        title: 'Large Files',
        onTap: onFiles,
      ),
      _QuickToolData(
        key: const Key('quick_apps'),
        icon: Icons.apps_outlined,
        tint: AppColors.indigoAccent,
        surface: AppColors.softIndigo,
        title: 'Apps',
        onTap: onApps,
      ),
      _QuickToolData(
        key: const Key('quick_permissions'),
        icon: Icons.lock_outline,
        tint: AppColors.cleanupOrange,
        surface: AppColors.softOrange,
        title: 'Storage',
        onTap: onPermissions,
      ),
    ];

    return Column(
      key: const Key('quick_tools_section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _QuickToolsHeader(dense: textScale > 1.3),
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

class _QuickToolsHeader extends StatelessWidget {
  const _QuickToolsHeader({required this.dense});

  final bool dense;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

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
      child: dense
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                heading,
                const SizedBox(height: 2),
                trailing,
              ],
            )
          : Row(
              children: <Widget>[
                Expanded(child: heading),
                const SizedBox(width: AppSpacing.xs),
                // Flexible keeps the note on one line when it fits but lets
                // it wrap at large text scales instead of overflowing.
                Flexible(child: trailing),
              ],
            ),
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
    required this.onTap,
  });

  final Key key;
  final IconData icon;
  final Color tint;
  final Color surface;
  final String title;
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
              AppIconContainer(
                icon: data.icon,
                accent: data.tint,
                backgroundColor: isDark
                    ? data.tint.withValues(alpha: 0.22)
                    : data.surface,
                size: 42,
                iconSize: 21,
              ),
              const SizedBox(height: 8),
              Text(
                data.title,
                maxLines: 2,
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
            ],
          ),
        ),
      ),
    );
  }
}
