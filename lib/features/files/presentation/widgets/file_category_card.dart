import 'package:flutter/material.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';

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
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color accent = colorForCategory(summary.category);
    final bool empty = summary.isEmpty;

    return Card(
      clipBehavior: Clip.antiAlias,
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
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: empty ? 0.10 : 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      iconForCategory(summary.category),
                      size: 21,
                      color: empty ? colors.onSurfaceVariant : accent,
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
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
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
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Text(
                ByteFormatter.format(summary.totalBytes),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: empty ? colors.onSurfaceVariant : accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
