import 'package:flutter/material.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/files/domain/file_selection.dart';

/// Bottom action bar shown whenever files are selected in a cleaner.
///
/// One implementation shared by every selectable screen, so the Delete action
/// cannot be present in one tool and missing in another, and so there is only
/// ever one route into the Phase 12 safe-delete flow.
///
/// ## Placement
///
/// This belongs in the screen's body `Column`, directly below the `Expanded`
/// scrollable list — **not** in `Scaffold.bottomNavigationBar`.
///
/// ## Why the width is bounded explicitly
///
/// A `Column` gives its children **unbounded width** on the cross axis. With a
/// bare `Row` inside, the row laid out at infinite width: `Flexible` cannot
/// divide infinity, and the buttons were handed
/// `BoxConstraints(w=Infinity, 56.0<=h<=Infinity)` — the 56 being the
/// Material 3 minimum button height — which throws *BoxConstraints forces an
/// infinite width* and takes the whole screen down with it.
///
/// `LayoutBuilder` reports the real width the parent offers, and the row is
/// tightened to it. Note that `SizedBox(width: double.infinity)` would **not**
/// fix this: it sets exactly the infinite width that caused the crash.
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

  /// Material 3's minimum button height. Applied as a *height* only — never a
  /// width — so a button can never request infinite horizontal space.
  static const double _minButtonHeight = 48;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    final int deletable = deletableCount ?? selection.count;
    final bool canDelete = deletable > 0;

    return Material(
      key: barKey,
      color: colors.surfaceContainerHighest,
      elevation: 8,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // Fall back to the screen width if an ancestor really is unbounded,
          // rather than propagating infinity down to the buttons.
          final double barWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;

          return SizedBox(
            width: barWidth,
            child: Padding(
              // The body's SafeArea already clears the navigation bar.
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                children: <Widget>[
                  // Takes the leftover space and ellipsises, so the buttons
                  // keep their intrinsic width on narrow phones.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          '${selection.count} selected',
                          key: countKey,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          canDelete && deletable < selection.count
                              // Be explicit when Android protects some.
                              ? '${ByteFormatter.format(selection.totalBytes)}'
                                    ' · $deletable can be deleted'
                              : ByteFormatter.format(selection.totalBytes),
                          key: bytesKey,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    key: clearKey,
                    style: TextButton.styleFrom(
                      // Height only. A minimumSize with an infinite or very
                      // large width would reintroduce the crash.
                      minimumSize: const Size(0, _minButtonHeight),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: onClear,
                    child: const Text('Clear'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton.icon(
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
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
