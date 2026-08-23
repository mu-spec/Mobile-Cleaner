import 'package:flutter/material.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/files/domain/file_selection.dart';

/// Bottom action bar shown whenever files are selected in a cleaner.
///
/// The bar belongs directly below the screen's Expanded list. At normal
/// widths it is one compact row. Narrow screens and large system text use a
/// two-row layout so the summary and actions never compete for the same
/// horizontal space.
class SelectionActionBar extends StatelessWidget {
  const SelectionActionBar({
    required this.selection,
    required this.onClear,
    required this.onDelete,
    required this.barKey,
    required this.countKey,
    required this.bytesKey,
    required this.clearKey,
    required this.deleteKey,
    this.deletableCount,
    super.key,
  });

  final FileSelection selection;
  final VoidCallback onClear;
  final VoidCallback onDelete;

  /// Per-screen keys retained for existing tests and automation.
  final Key barKey;
  final Key countKey;
  final Key bytesKey;
  final Key clearKey;
  final Key deleteKey;

  /// Number of selected items Android can actually delete.
  /// Null means every selected item is deletable.
  final int? deletableCount;

  static const double _minButtonHeight = 48;
  static const double _stackBreakpoint = 380;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final int deletable = deletableCount ?? selection.count;
    final bool canDelete = deletable > 0;
    final double textScale = MediaQuery.textScalerOf(context).scale(1);

    return Material(
      key: barKey,
      color: colors.surfaceContainerHighest,
      elevation: 8,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double barWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          final bool stacked =
              barWidth < _stackBreakpoint || textScale > 1.3;

          final Widget summary = _SelectionSummary(
            selection: selection,
            deletable: deletable,
            canDelete: canDelete,
            countKey: countKey,
            bytesKey: bytesKey,
            allowTwoLines: stacked,
          );
          final Widget clearButton = TextButton(
            key: clearKey,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, _minButtonHeight),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: onClear,
            child: const Text('Clear'),
          );
          final Widget deleteButton = FilledButton.icon(
            key: deleteKey,
            style: FilledButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
              minimumSize: const Size(0, _minButtonHeight),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onPressed: canDelete ? onDelete : null,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Delete'),
          );

          return SizedBox(
            width: barWidth,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              child: stacked
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        summary,
                        const SizedBox(height: 4),
                        Row(
                          children: <Widget>[
                            Expanded(child: clearButton),
                            const SizedBox(width: 8),
                            Expanded(child: deleteButton),
                          ],
                        ),
                      ],
                    )
                  : Row(
                      children: <Widget>[
                        Expanded(child: summary),
                        const SizedBox(width: 8),
                        clearButton,
                        const SizedBox(width: 4),
                        deleteButton,
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }
}

class _SelectionSummary extends StatelessWidget {
  const _SelectionSummary({
    required this.selection,
    required this.deletable,
    required this.canDelete,
    required this.countKey,
    required this.bytesKey,
    required this.allowTwoLines,
  });

  final FileSelection selection;
  final int deletable;
  final bool canDelete;
  final Key countKey;
  final Key bytesKey;
  final bool allowTwoLines;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final String bytesLabel = canDelete && deletable < selection.count
        ? '${ByteFormatter.format(selection.totalBytes)}'
              ' · $deletable can be deleted'
        : ByteFormatter.format(selection.totalBytes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '${selection.count} selected',
          key: countKey,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          bytesLabel,
          key: bytesKey,
          maxLines: allowTwoLines ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}
