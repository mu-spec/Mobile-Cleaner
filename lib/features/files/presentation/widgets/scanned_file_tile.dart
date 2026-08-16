import 'package:flutter/material.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/core/utils/date_formatter.dart';
import 'package:mobile_cleaner/core/utils/duration_formatter.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/file_thumbnail.dart';

/// A single row in a file list: thumbnail/icon, name, size, and date.
class ScannedFileTile extends StatelessWidget {
  const ScannedFileTile({
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
  /// use, which keeps every existing caller unchanged.
  final bool? selected;

  /// When true the row shows a checkbox instead of the details affordance.
  final bool selectionMode;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return ListTile(
      key: Key('file_tile_${file.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      leading: FileThumbnail(file: file),
      title: Text(
        file.name,
        key: Key('file_name_${file.id}'),
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
              key: Key('file_size_${file.id}'),
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
            Flexible(
              child: Text(
                DateFormatter.relative(file.dateModified),
                key: Key('file_date_${file.id}'),
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
              key: Key('file_checkbox_${file.id}'),
              value: selected ?? false,
              onChanged: onTap == null ? null : (_) => onTap!(),
            )
          : Icon(
              Icons.info_outline_rounded,
              size: 19,
              color: colors.onSurfaceVariant,
            ),
      selected: selected ?? false,
      selectedTileColor: colors.primary.withValues(alpha: 0.08),
      onTap: onTap ?? () => showFileDetails(context, file),
      onLongPress: onLongPress,
    );
  }
}

/// Bottom sheet describing one file in full.
void showFileDetails(BuildContext context, ScannedFile file) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  FileThumbnail(file: file, size: 54),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      file.name,
                      style: Theme.of(sheetContext).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _DetailRow(
                label: 'Type',
                value: file.mimeType ?? file.category.label,
              ),
              _DetailRow(
                label: 'Size',
                value: ByteFormatter.format(file.sizeBytes),
              ),
              if (file.isVideo)
                _DetailRow(
                  label: 'Length',
                  value: DurationFormatter.format(file.duration),
                ),
              _DetailRow(
                label: 'Modified',
                value: DateFormatter.format(file.dateModified),
              ),
              _DetailRow(
                label: 'Location',
                value: file.path.isNotEmpty ? file.path : file.uri,
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
