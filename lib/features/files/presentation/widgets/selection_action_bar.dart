import 'package:flutter/material.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/files/domain/file_selection.dart';

/// Bottom action bar shown whenever files are selected in a cleaner.
///
/// One implementation shared by every cleaner, so the Delete action cannot be
/// present in one tool and missing in another.
///
/// Laid out defensively, because the previous per-screen version was a fixed
/// [Row] that could overflow on narrow devices or at large system font
/// scales, pushing the Delete button off-screen:
///
/// - the count and size column is [Flexible] and ellipsises rather than
///   forcing the row wider than the screen,
/// - the Delete button keeps its intrinsic width so it is never squeezed out,
/// - a [SafeArea] with `top: false` keeps it clear of the gesture inset.
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
    super.key,
  });

  final FileSelection selection;
  final VoidCallback onClear;
  final VoidCallback onDelete;

  /// Per-screen keys, so existing tests and tooling keep working.
  final Key barKey;
  final Key countKey;
  final Key bytesKey;
  final Key clearKey;
  final Key deleteKey;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Material(
      key: barKey,
      color: colors.surfaceContainerHighest,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: <Widget>[
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '${selection.count} selected',
                      key: countKey,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      ByteFormatter.format(selection.totalBytes),
                      key: bytesKey,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: clearKey,
                onPressed: onClear,
                child: const Text('Clear'),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                key: deleteKey,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: colors.onError,
                ),
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Delete'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
