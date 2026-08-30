import 'package:flutter/material.dart';
import 'package:mobile_cleaner/core/ui/haptics.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/core/utils/date_formatter.dart';
import 'package:mobile_cleaner/core/utils/duration_formatter.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/file_thumbnail.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/photo_tool_ui.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// A single row in a file list: thumbnail/icon, name, size, and date.
class ScannedFileTile extends StatelessWidget {
  const ScannedFileTile({
    required this.file,
    this.onTap,
    this.onLongPress,
    this.onSelectionToggle,
    this.selected,
    this.selectionMode = false,
    super.key,
  });

  final ScannedFile file;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Optional checkbox callback when row taps and selection taps differ.
  /// Cleaners can omit it to keep their existing tap-to-select behavior.
  final VoidCallback? onSelectionToggle;

  /// Whether this row is currently selected. Null means selection is not in
  /// use, which keeps every existing caller unchanged.
  final bool? selected;

  /// When true the row shows a checkbox instead of the details affordance.
  final bool selectionMode;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final VoidCallback? selectionToggle = onSelectionToggle ?? onTap;

    return ListTile(
      key: Key('file_tile_${file.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      leading: FileThumbnail(file: file),
      title: Text(
        file.name,
        key: Key('file_name_${file.id}'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool stackMetadata =
                constraints.maxWidth < 200 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.3;
            final Widget size = Text(
              ByteFormatter.format(file.sizeBytes),
              key: Key('file_size_${file.id}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            );
            final Widget date = Text(
              DateFormatter.relative(file.dateModified),
              key: Key('file_date_${file.id}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            );

            if (stackMetadata) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[size, date],
              );
            }
            return Row(
              children: <Widget>[
                Flexible(child: size),
                Text(
                  '  ·  ',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
                Expanded(child: date),
              ],
            );
          },
        ),
      ),
      trailing: selectionMode
          ? Checkbox(
              key: Key('file_checkbox_${file.id}'),
              // Names the row, so a screen reader announces "beach.jpg,
              // checkbox" rather than an unlabelled control in a long list.
              semanticLabel: file.name,
              value: selected ?? false,
              onChanged: selectionToggle == null
                  ? null
                  : (_) {
                      Haptics.selection();
                      selectionToggle();
                    },
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
    backgroundColor: PhotoToolUi.surface(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (BuildContext sheetContext) {
      return SafeArea(
        child: SingleChildScrollView(
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          file.name,
                          style: Theme.of(sheetContext).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: <Widget>[
                            PhosphorIcon(
                              PhosphorIconsDuotone.shieldCheck,
                              size: 15,
                              color: PhotoToolUi.primary(sheetContext),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'File details',
                              style: Theme.of(sheetContext).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(sheetContext)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Divider(color: PhotoToolUi.border(sheetContext)),
              const SizedBox(height: 12),
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
    final Text labelText = Text(
      label,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool stack =
              constraints.maxWidth < 320 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3;
          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                labelText,
                const SizedBox(height: 4),
                Text(value),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(width: 92, child: labelText),
              Expanded(child: Text(value)),
            ],
          );
        },
      ),
    );
  }
}
