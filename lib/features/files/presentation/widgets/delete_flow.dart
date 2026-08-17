import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/core/ui/haptics.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/files/data/delete_repository.dart';
import 'package:mobile_cleaner/features/files/domain/delete_result.dart';
import 'package:mobile_cleaner/features/files/domain/file_selection.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/screens/cleanup_complete_screen.dart';
import 'package:mobile_cleaner/features/history/presentation/providers/cleanup_history_provider.dart';
import 'package:mobile_cleaner/features/storage/presentation/providers/storage_overview_provider.dart';

/// Runs the shared delete flow: Review, Confirm, Delete, Result.
///
/// Returns the [DeleteResult] so the caller can drop deleted files from its
/// list, or `null` when the user backed out before anything was deleted.
///
/// Every cleaner uses this one path, so the safety rules — an explicit
/// in-app confirmation, an irreversible-action warning, and honest reporting
/// of partial failures — cannot drift between tools.
Future<DeleteResult?> runDeleteFlow({
  required BuildContext context,
  required WidgetRef ref,
  required FileSelection selection,
}) async {
  if (selection.isEmpty) {
    return null;
  }

  // Only send what Android can act on. A file:// row from the legacy scan
  // cannot be deleted through MediaStore or SAF, so including it would
  // guarantee a failure the user did not need to see.
  final List<ScannedFile> files = selection.deletableFiles.toList(
    growable: false,
  );
  if (files.isEmpty) {
    return null;
  }

  // Step 1 and 2: review the selection, then confirm.
  final bool confirmed =
      await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (BuildContext sheetContext) =>
            _ReviewSheet(files: files, totalBytes: selection.totalBytes),
      ) ??
      false;

  if (!confirmed || !context.mounted) {
    return null;
  }

  // Step 3: delete. The platform may raise its own confirmation on top.
  //
  // The progress dialog is pushed with its own navigator entry and closed by
  // that entry's context, so it can never pop the caller's route even if the
  // delete finishes before the dialog finishes mounting.
  final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
  bool progressVisible = true;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (BuildContext dialogContext) => const _DeletingDialog(),
    ).then((_) => progressVisible = false),
  );

  final DeleteResult result = await ref
      .read(deleteRepositoryProvider)
      .deleteFiles(files);

  if (progressVisible && navigator.canPop()) {
    navigator.pop();
  }

  if (!context.mounted) {
    return result;
  }

  // Step 4: report exactly what happened.
  //
  // When files really went, show the full Cleanup Complete screen. Storage is
  // invalidated first so the screen's "free storage now" is read fresh from
  // the device rather than reusing a value cached before the deletion.
  //
  // Nothing is awaited, so the caller refreshes its list as soon as the delete
  // lands rather than waiting for the user to dismiss anything.
  if (result.deletedCount > 0) {
    Haptics.success();
    ref.invalidate(storageOverviewProvider);
    // Record the cleanup here, in the one shared flow, so every tool's
    // deletions are logged and no tool can forget to. Not awaited: history is
    // a convenience and must not delay the result screen.
    unawaited(
      recordCleanup(
        ref,
        filesRemoved: result.deletedCount,
        bytesRecovered: result.freedBytes,
      ),
    );
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext routeContext) =>
              CleanupCompleteScreen(result: result),
        ),
      ),
    );
    return result;
  }

  // Nothing was removed, so a dialog is the proportionate response.
  unawaited(
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => _ResultDialog(result: result),
    ),
  );

  return result;
}

/// Step 1 and 2: what will be removed, and the confirmation.
class _ReviewSheet extends StatelessWidget {
  const _ReviewSheet({required this.files, required this.totalBytes});

  final List<ScannedFile> files;
  final int totalBytes;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    // Show a readable sample rather than a thousand rows.
    final List<ScannedFile> preview = files.take(8).toList(growable: false);
    final int remaining = files.length - preview.length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Review before deleting',
              key: const Key('delete_review_title'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              '${files.length} ${files.length == 1 ? 'file' : 'files'} · '
              '${ByteFormatter.format(totalBytes)}',
              key: const Key('delete_review_summary'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: SingleChildScrollView(
                child: Column(
                  children: <Widget>[
                    for (final ScannedFile file in preview)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                file.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              ByteFormatter.format(file.sizeBytes),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    if (remaining > 0)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'and $remaining more',
                          key: const Key('delete_review_more'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 20,
                    color: colors.onErrorContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This cannot be undone. Deleted files are not moved to '
                      'a recycle bin.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Android may ask you to confirm again.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    key: const Key('delete_cancel'),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('delete_confirm'),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.error,
                      foregroundColor: colors.onError,
                    ),
                    onPressed: () {
                      // Heavier than a selection tap: this is the moment an
                      // irreversible action is committed.
                      Haptics.warning();
                      Navigator.of(context).pop(true);
                    },
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: Text('Delete ${files.length}'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeletingDialog extends StatelessWidget {
  const _DeletingDialog();

  @override
  Widget build(BuildContext context) {
    return const AlertDialog(
      key: Key('delete_progress'),
      content: Row(
        children: <Widget>[
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          SizedBox(width: 18),
          Expanded(child: Text('Deleting…')),
        ],
      ),
    );
  }
}

/// Step 5: the honest outcome, including partial failures.
class _ResultDialog extends StatelessWidget {
  const _ResultDialog({required this.result});

  final DeleteResult result;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    final String title;
    final IconData icon;
    final Color iconColor;

    if (result.userCancelled) {
      title = 'Nothing deleted';
      icon = Icons.info_outline_rounded;
      iconColor = colors.onSurfaceVariant;
    } else if (result.isCompleteSuccess) {
      title = 'Deleted';
      icon = Icons.check_circle_outline_rounded;
      iconColor = colors.primary;
    } else if (result.isPartialSuccess) {
      title = 'Partly deleted';
      icon = Icons.warning_amber_rounded;
      iconColor = colors.error;
    } else {
      title = 'Could not delete';
      icon = Icons.error_outline_rounded;
      iconColor = colors.error;
    }

    return AlertDialog(
      key: const Key('delete_result_dialog'),
      icon: Icon(icon, color: iconColor, size: 34),
      title: Text(title, key: const Key('delete_result_title')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (result.deletedCount > 0)
            Text(
              'Removed ${result.deletedCount} '
              '${result.deletedCount == 1 ? 'file' : 'files'} and freed '
              '${ByteFormatter.format(result.freedBytes)}.',
              key: const Key('delete_result_freed'),
            ),
          if (result.userCancelled && result.deletedCount == 0)
            const Text('The deletion was cancelled.'),
          if (result.failureCount > 0) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              '${result.failureCount} '
              '${result.failureCount == 1 ? 'file' : 'files'} could not be '
              'removed.',
              key: const Key('delete_result_failed'),
              style: TextStyle(color: colors.error),
            ),
            const SizedBox(height: 4),
            Text(
              result.failures.first.reason,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        FilledButton(
          key: const Key('delete_result_done'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
