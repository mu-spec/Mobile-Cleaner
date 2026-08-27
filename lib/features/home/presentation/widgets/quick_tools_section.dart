import 'package:flutter/material.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';
import 'package:mobile_cleaner/app/theme/app_tokens.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/home_section.dart';
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
        iconKey: const Key('quick_photos_icon_tile'),
        icon: PhosphorIconsDuotone.image,
        tint: AppColors.photoAccent,
        surface: AppColors.softPhoto,
        title: 'Photos',
        subtitle: 'Duplicates',
        onTap: onPhotos,
      ),
      _QuickToolData(
        key: const Key('quick_files'),
        iconKey: const Key('quick_files_icon_tile'),
        icon: PhosphorIconsDuotone.folder,
        tint: AppColors.actionBlue,
        surface: AppColors.softBlue,
        title: 'Large Files',
        subtitle: 'Big files',
        onTap: onFiles,
      ),
      _QuickToolData(
        key: const Key('quick_apps'),
        iconKey: const Key('quick_apps_icon_tile'),
        icon: PhosphorIconsDuotone.squaresFour,
        tint: AppColors.indigoAccent,
        surface: AppColors.softIndigo,
        title: 'Apps',
        subtitle: 'App sizes',
        onTap: onApps,
      ),
      _QuickToolData(
        key: const Key('quick_permissions'),
        iconKey: const Key('quick_permissions_icon_tile'),
        icon: PhosphorIconsDuotone.lock,
        tint: AppColors.cleanupOrange,
        surface: AppColors.softOrange,
        title: 'Storage Access',
        subtitle: 'Permissions',
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
          padding: const EdgeInsets.only(bottom: HomeMetrics.headingGap),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Semantics(
                header: true,
                child: Text(
                  key: const Key('quick_tools_title'),
                  'Quick Tools',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? theme.colorScheme.onSurface
                        : AppColors.navy,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Four-across card
        Card(
          key: const Key('quick_tools_card'),
          elevation: isDark ? 0 : 2,
          shadowColor: AppColors.navy.withValues(alpha: 0.07),
          surfaceTintColor: Colors.transparent,
          color: isDark ? Colors.transparent : AppColors.card,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: isDark
                  ? theme.colorScheme.outlineVariant
                  : AppColors.border,
            ),
          ),
          child: Ink(
            key: const Key('quick_tools_surface'),
            decoration: BoxDecoration(
              gradient: isDark
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        Color(0xFF152235),
                        AppColors.darkSurfaceElevated,
                      ],
                    )
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (int i = 0; i < tools.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(width: AppSpacing.xxs),
                    Expanded(
                      child: _QuickToolShortcut(data: tools[i], isDark: isDark),
                    ),
                  ],
                ],
              ),
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
    required this.iconKey,
    required this.icon,
    required this.tint,
    required this.surface,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final Key key;
  final Key iconKey;
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
    final Color iconColor = isDark
        ? Color.lerp(data.tint, Colors.white, 0.20)!
        : data.tint;
    final double textScale = MediaQuery.textScalerOf(context).scale(1);
    final double titleHeight = 28 * textScale.clamp(1.0, 1.5);

    return Semantics(
      button: true,
      label: data.title,
      child: InkWell(
        key: data.key,
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: data.tint.withValues(alpha: 0.12),
        highlightColor: data.tint.withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 2,
            vertical: AppSpacing.xxs,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Layered, lightly elevated icon tile. Every shortcut uses the
              // same geometry while retaining its own feature colour.
              Container(
                key: data.iconKey,
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? <Color>[
                            Color.lerp(
                              theme.colorScheme.surfaceContainer,
                              data.tint,
                              0.14,
                            )!,
                            Color.lerp(
                              theme.colorScheme.surfaceContainer,
                              data.tint,
                              0.055,
                            )!,
                          ]
                        : <Color>[
                            Color.lerp(data.surface, Colors.white, 0.35)!,
                            data.surface,
                          ],
                  ),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: iconColor.withValues(alpha: isDark ? 0.22 : 0.13),
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: isDark
                          ? Colors.black.withValues(alpha: 0.18)
                          : data.tint.withValues(alpha: 0.13),
                      blurRadius: isDark ? 10 : 14,
                      offset: Offset(0, isDark ? 3 : 5),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    if (!isDark) ...<Widget>[
                      Positioned(
                        right: -7,
                        top: -7,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: data.tint.withValues(alpha: 0.07),
                          ),
                        ),
                      ),
                    ],
                    PhosphorIcon(
                      data.icon,
                      size: 24,
                      color: iconColor,
                      duotoneSecondaryColor: iconColor,
                      duotoneSecondaryOpacity: isDark ? 0.42 : 0.52,
                    ),
                    if (!isDark) ...<Widget>[
                      Positioned(
                        left: 8,
                        top: 7,
                        child: Container(
                          width: 12,
                          height: 2,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            color: Colors.white.withValues(alpha: 0.62),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 9),
              SizedBox(
                height: titleHeight,
                child: Center(
                  child: Text(
                    data.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      letterSpacing: -0.15,
                      color: isDark
                          ? theme.colorScheme.onSurface
                          : AppColors.navy,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                data.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 9.75,
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
