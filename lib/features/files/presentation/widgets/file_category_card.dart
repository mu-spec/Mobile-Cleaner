import 'package:flutter/material.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Icon used for a category across the Files feature.
IconData iconForCategory(FileCategory category) {
  return switch (category) {
    FileCategory.images => Icons.photo_library_rounded,
    FileCategory.videos => Icons.videocam_rounded,
    FileCategory.audio => Icons.audiotrack_rounded,
    FileCategory.documents => Icons.description_rounded,
    FileCategory.downloads => Icons.download_rounded,
    FileCategory.apks => Icons.android_rounded,
    FileCategory.other => Icons.insert_drive_file_rounded,
  };
}

/// Accent colour used for a category tile.
Color colorForCategory(FileCategory category) {
  return switch (category) {
    FileCategory.images => const Color(0xFF0891B2),
    FileCategory.videos => const Color(0xFF7C3AED),
    FileCategory.audio => const Color(0xFFDB2777),
    FileCategory.documents => const Color(0xFF0F766E),
    FileCategory.downloads => const Color(0xFFF59E0B),
    FileCategory.apks => const Color(0xFF16A34A),
    FileCategory.other => const Color(0xFF64748B),
  };
}

IconData _premiumIconForCategory(FileCategory category) {
  return switch (category) {
    FileCategory.images => PhosphorIconsDuotone.imagesSquare,
    FileCategory.videos => PhosphorIconsDuotone.videoCamera,
    FileCategory.audio => PhosphorIconsDuotone.musicNotes,
    FileCategory.documents => PhosphorIconsDuotone.fileText,
    FileCategory.downloads => PhosphorIconsDuotone.downloadSimple,
    FileCategory.apks => PhosphorIconsDuotone.androidLogo,
    FileCategory.other => PhosphorIconsDuotone.files,
  };
}

/// Grid tile summarising one category on the Files tab.
class FileCategoryCard extends StatelessWidget {
  const FileCategoryCard({
    required this.summary,
    required this.onTap,
    super.key,
  });

  final FileCategorySummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;
    final Color accent = colorForCategory(summary.category);
    final bool empty = summary.isEmpty;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceElevated : AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
        ),
        boxShadow: <BoxShadow>[
          if (!isDark)
            BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.045),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: Key('category_card_${summary.category.key}'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      key: Key('category_icon_${summary.category.key}'),
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: accent.withValues(
                          alpha: isDark
                              ? 0.17
                              : empty
                              ? 0.09
                              : 0.14,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: accent.withValues(alpha: isDark ? 0.22 : 0.06),
                        ),
                      ),
                      child: Center(
                        child: PhosphorIcon(
                          _premiumIconForCategory(summary.category),
                          size: 25,
                          color: empty ? colors.onSurfaceVariant : accent,
                          duotoneSecondaryColor: Color.lerp(
                            accent,
                            Colors.white,
                            0.58,
                          ),
                          duotoneSecondaryOpacity: 1,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  summary.category.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  empty
                      ? 'Empty'
                      : '${summary.fileCount} '
                            '${summary.fileCount == 1 ? 'file' : 'files'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  ByteFormatter.format(summary.totalBytes),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: empty ? colors.onSurfaceVariant : accent,
                    fontWeight: FontWeight.w800,
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
