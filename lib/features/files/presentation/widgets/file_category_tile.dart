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
    FileCategory.other => Icons.insert_drive_file_rounded,
  };
}

class FileCategoryTile extends StatelessWidget {
  const FileCategoryTile({
    required this.summary,
    required this.totalBytes,
    required this.onTap,
    super.key,
  });

  final FileCategorySummary summary;
  final int totalBytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final double fraction = totalBytes == 0
        ? 0
        : (summary.totalBytes / totalBytes).clamp(0.0, 1.0);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        key: Key('category_tile_${summary.category.key}'),
        borderRadius: BorderRadius.circular(16),
        onTap: summary.isEmpty ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  iconForCategory(summary.category),
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      summary.category.label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      summary.isEmpty
                          ? 'No files found'
                          : '${summary.fileCount} '
                                '${summary.fileCount == 1 ? 'file' : 'files'}',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: fraction,
                        minHeight: 6,
                        backgroundColor: colors.surfaceContainerHighest,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    ByteFormatter.format(summary.totalBytes),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
