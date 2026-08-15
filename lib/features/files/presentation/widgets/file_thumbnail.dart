import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/thumbnail_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/file_category_card.dart';

/// Leading visual for a file row.
///
/// Shows a real thumbnail for images and videos, and a category icon for
/// everything else. Any failure falls back to the icon rather than an error.
class FileThumbnail extends ConsumerWidget {
  const FileThumbnail({required this.file, this.size = 44, super.key});

  final ScannedFile file;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!file.supportsThumbnail) {
      return _CategoryIcon(file: file, size: size);
    }

    final AsyncValue<Uint8List?> thumbnail = ref.watch(thumbnailProvider(file));

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: size,
        height: size,
        child: thumbnail.when(
          loading: () => _ThumbnailPlaceholder(size: size),
          error: (Object error, StackTrace stackTrace) =>
              _CategoryIcon(file: file, size: size),
          data: (Uint8List? bytes) {
            if (bytes == null || bytes.isEmpty) {
              return _CategoryIcon(file: file, size: size);
            }
            return Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Image.memory(
                  bytes,
                  key: Key('thumbnail_image_${file.id}'),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  // A corrupt thumbnail must not take down the list.
                  errorBuilder:
                      (
                        BuildContext context,
                        Object error,
                        StackTrace? stackTrace,
                      ) => _CategoryIcon(file: file, size: size),
                ),
                if (file.category == FileCategory.videos)
                  const _VideoBadge(),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CategoryIcon extends StatelessWidget {
  const _CategoryIcon({required this.file, required this.size});

  final ScannedFile file;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Color accent = colorForCategory(file.category);
    return Container(
      key: Key('thumbnail_icon_${file.id}'),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        iconForCategory(file.category),
        size: size * 0.48,
        color: accent,
      ),
    );
  }
}

class _ThumbnailPlaceholder extends StatelessWidget {
  const _ThumbnailPlaceholder({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}

/// Small play glyph so videos are distinguishable from photos at a glance.
class _VideoBadge extends StatelessWidget {
  const _VideoBadge();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: EdgeInsets.all(3),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0xB3000000),
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: EdgeInsets.all(2),
            child: Icon(
              Icons.play_arrow_rounded,
              size: 12,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
