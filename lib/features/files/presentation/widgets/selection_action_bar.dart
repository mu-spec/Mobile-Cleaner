import 'package:flutter/material.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/files/domain/file_selection.dart';

/// Bottom action bar shown whenever files are selected in a cleaner.
///
/// One implementation shared by every selectable screen, so the Delete action
/// cannot be present in one tool and missing in another, and so there is only
/// ever one route into the Phase 12 safe-delete flow.
///
/// ## Staying above the system navigation bar
///
/// The screens wrap their `body` in a `SafeArea`. That consumes the bottom
/// inset *before* the `Scaffold` lays out `bottomNavigationBar`, so a nested
/// `SafeArea` here would find nothing left to pad and the bar would sit
/// underneath the gesture pill or button bar — visible in a screenshot, but
/// unreachable on a real device.
///
/// Reading `MediaQuery.viewPaddingOf` gives the true system inset regardless
/// of what an ancestor already consumed, so the bar always clears it.
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

  /// Per-screen keys, so existing tests and tooling keep working.
  final Key barKey;
  final Key countKey;
  final Key bytesKey;
  final Key clearKey;
  final Key deleteKey;

  /// How many of the selected items Android will actually let us delete.
  ///
  /// Null means "all of them". When zero, Delete is disabled rather than
  /// letting the user start a flow the platform will certainly refuse.
  final int? deletableCount;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    // The true system inset, even though an ancestor SafeArea consumed it.
    final double systemInset = MediaQuery.viewPaddingOf(context).bottom;
    final int deletable = deletableCount ?? selection.count;
    final bool canDelete = deletable > 0;

    return Material(
      key: barKey,
      color: colors.surfaceContainerHighest,
      elevation: 8,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + systemInset),
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
                    canDelete && deletable < selection.count
                        // Be explicit when Android protects some of them.
                        ? '${ByteFormatter.format(selection.totalBytes)} · '
                              '$deletable can be deleted'
                        : ByteFormatter.format(selection.totalBytes),
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
              onPressed: canDelete ? onDelete : null,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }
}
