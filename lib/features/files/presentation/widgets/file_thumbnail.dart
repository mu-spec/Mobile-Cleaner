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

  /// Target decode size in physical pixels.
  ///
  /// Scaled by the device pixel ratio so the image is not soft on a
  /// high-density screen, and clamped so a very large logical size cannot ask
  /// for an enormous bitmap.
  int _decodeExtent(BuildContext context) {
    final double ratio = MediaQuery.devicePixelRatioOf(context);
    final double physical = size * (ratio <= 0 ? 1 : ratio);
    return physical.clamp(32, 512).round();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!file.supportsThumbnail) {
      return _CategoryIcon(file: file, size: size);
    }

    // One shared request size for every tile, so a 44px row and a 118px cell
    // reuse the same cached bytes instead of decoding the file twice. 128 is
    // large enough for the biggest tile the app draws.
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
                  // Decode to the size actually drawn. Without this, Flutter
                  // decodes at full resolution and stores that in the image
                  // cache — a 44px tile could hold a multi-megabyte bitmap,
                  // and a long list would evict everything useful.
                  cacheWidth: _decodeExtent(context),
                  cacheHeight: _decodeExtent(context),
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
