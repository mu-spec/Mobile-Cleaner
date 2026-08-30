import 'package:flutter/material.dart';
import 'package:mobile_cleaner/core/ui/haptics.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/core/utils/date_formatter.dart';
import 'package:mobile_cleaner/core/utils/duration_formatter.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/file_thumbnail.dart';

/// A row in the Videos section: thumbnail, name, duration, size, and date.
///
/// A dedicated tile rather than [ScannedFileTile] because a video row carries
/// one more fact — its length — and length belongs on the thumbnail, where a
/// viewer expects it, rather than crammed into the subtitle.
class VideoTile extends StatelessWidget {
  const VideoTile({
    required this.file,
    this.onTap,
    this.onLongPress,
    this.selected,
    this.selectionMode = false,
    super.key,
  });

  final ScannedFile file;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Whether this row is currently selected. Null means selection is not in
  /// use.
  final bool? selected;

  /// When true the row shows a checkbox instead of the details affordance.
  final bool selectionMode;

  static const double _thumbSize = 60;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Duration? duration = file.duration;

    return ListTile(
      key: Key('video_tile_${file.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      leading: SizedBox(
        width: _thumbSize,
        height: _thumbSize,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            FileThumbnail(file: file, size: _thumbSize),
            // Length sits on the thumbnail, as it does in every video app.
            Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xCC000000),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 1,
                    ),
                    child: Text(
                      DurationFormatter.format(duration),
                      key: Key('video_duration_${file.id}'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      title: Text(
        file.name,
        key: Key('video_name_${file.id}'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          children: <Widget>[
            Text(
              ByteFormatter.format(file.sizeBytes),
              key: Key('video_size_${file.id}'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            Text(
              '  ·  ',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            // Flexible, not fixed: a long relative date must ellipsise rather
            // than overflow the row on a narrow phone.
            Flexible(
              child: Text(
                DateFormatter.relative(file.dateModified),
                key: Key('video_date_${file.id}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
      trailing: selectionMode
          ? Checkbox(
              key: Key('video_checkbox_${file.id}'),
              // Names the row, so a screen reader announces "beach.jpg,
              // checkbox" rather than an unlabelled control in a long list.
              semanticLabel: file.name,
              value: selected ?? false,
              onChanged: onTap == null
                  ? null
                  : (_) {
                      Haptics.selection();
                      onTap!();
                    },
            )
          : Icon(
              Icons.info_outline_rounded,
              size: 19,
              color: colors.onSurfaceVariant,
            ),
      selected: selected ?? false,
      selectedTileColor: colors.primary.withValues(alpha: 0.08),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
