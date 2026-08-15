import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/files/domain/apk_summary.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_selection.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/apk_provider.dart';
import 'package:mobile_cleaner/features/files/domain/delete_result.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/delete_flow.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/files_status_views.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/scanned_file_tile.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/selection_action_bar.dart';

/// APK Cleaner: find installer packages left on the device and remove them.
///
/// Deletion runs through the shared Review, Confirm, Delete, Result flow, so
/// nothing is removed without an explicit in-app confirmation.
class ApkCleanerScreen extends ConsumerStatefulWidget {
  const ApkCleanerScreen({super.key});

  @override
  ConsumerState<ApkCleanerScreen> createState() => _ApkCleanerScreenState();
}

class _ApkCleanerScreenState extends ConsumerState<ApkCleanerScreen> {
  FileListSort _sort = FileListSort.largest;
  FileSelection _selection = const FileSelection.empty();

  void _toggle(ScannedFile file) {
    setState(() => _selection = _selection.toggle(file));
  }

  void _toggleAll(List<ScannedFile> visible) {
    setState(() {
      _selection = _selection.containsAll(visible)
          ? _selection.deselectAll(visible)
          : _selection.selectAll(visible);
    });
  }

  void _clearSelection() {
    setState(() => _selection = _selection.clear());
  }

  /// Runs the shared Review -> Confirm -> Delete -> Result flow, then drops
  /// whatever really went and rescans so the list reflects the device.
  Future<void> _deleteSelected() async {
    final DeleteResult? result = await runDeleteFlow(
      context: context,
      ref: ref,
      selection: _selection,
    );
    if (result == null || !mounted) {
      return;
    }
    if (result.deletedCount > 0) {
      setState(() {
        _selection = _selection.deselectAll(result.deletedFiles);
      });
      ref.invalidate(apkScanProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<ApkSummary> summary = ref.watch(apkSummaryProvider(_sort));
    final bool selecting = _selection.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        leading: selecting
            ? IconButton(
                key: const Key('apk_cancel_selection'),
                tooltip: 'Cancel selection',
                onPressed: _clearSelection,
                icon: const Icon(Icons.close_rounded),
              )
            : null,
        title: Text(
          selecting ? '${_selection.count} selected' : 'APK Cleaner',
          key: const Key('apk_title'),
        ),
        actions: <Widget>[
          if (!selecting) ...<Widget>[
            PopupMenuButton<FileListSort>(
              key: const Key('apk_sort_button'),
              tooltip: 'Sort',
              icon: const Icon(Icons.sort_rounded),
              initialValue: _sort,
              onSelected: (FileListSort value) =>
                  setState(() => _sort = value),
              itemBuilder: (BuildContext context) =>
                  <PopupMenuEntry<FileListSort>>[
                    for (final FileListSort option in FileListSort.values)
                      PopupMenuItem<FileListSort>(
                        key: Key('apk_sort_${option.name}'),
                        value: option,
                        child: Row(
                          children: <Widget>[
                            Icon(
                              option == _sort
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 18,
                              color: option == _sort
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 10),
                            Text(option.label),
                          ],
                        ),
                      ),
                  ],
            ),
            IconButton(
              key: const Key('apk_rescan'),
              tooltip: 'Rescan',
              onPressed: () => ref.invalidate(apkScanProvider),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: summary.when(
          loading: () => const FilesScanningView(),
          error: (Object error, StackTrace stackTrace) => FilesErrorView(
            error: error,
            onRetry: () => ref.invalidate(apkScanProvider),
            onPermissions: () => context.push(AppRoutes.permissions),
          ),
          data: (ApkSummary data) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(apkScanProvider);
              await ref.read(apkScanProvider.future);
            },
            child: data.isEmpty
                ? const _EmptyApks()
                : _ApkList(
                    summary: data,
                    selection: _selection,
                    onToggle: _toggle,
                    onToggleAll: () => _toggleAll(data.files),
                  ),
          ),
        ),
      ),
      bottomNavigationBar: selecting
          ? SelectionActionBar(
              selection: _selection,
              onClear: _clearSelection,
              onDelete: _deleteSelected,
              deletableCount: _selection.deletableCount,
              barKey: const Key('apk_selection_bar'),
              countKey: const Key('apk_selection_count'),
              bytesKey: const Key('apk_selection_bytes'),
              clearKey: const Key('apk_selection_clear'),
              deleteKey: const Key('apk_selection_delete'),
            )
          : null,
    );
  }
}

class _ApkList extends StatelessWidget {
  const _ApkList({
    required this.summary,
    required this.selection,
    required this.onToggle,
    required this.onToggleAll,
  });

  final ApkSummary summary;
  final FileSelection selection;
  final ValueChanged<ScannedFile> onToggle;
  final VoidCallback onToggleAll;

  @override
  Widget build(BuildContext context) {
    final bool allSelected = selection.containsAll(summary.files);

    return ListView(
      key: const Key('apk_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      // Extra bottom room while selecting, so the action bar never
      // covers the last row.
      padding: EdgeInsets.fromLTRB(16, 6, 16, selection.isEmpty ? 28 : 104),
      children: <Widget>[
        _TotalCard(summary: summary),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                summary.sort.label,
                key: const Key('apk_sort_label'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton.icon(
              key: const Key('apk_select_all'),
              onPressed: onToggleAll,
              icon: Icon(
                allSelected
                    ? Icons.remove_done_rounded
                    : Icons.done_all_rounded,
                size: 18,
              ),
              label: Text(allSelected ? 'Clear all' : 'Select all'),
            ),
          ],
        ),
        // Each row shows the installer's name, size, and date.
        for (final ScannedFile file in summary.files)
          ScannedFileTile(
            file: file,
            selectionMode: true,
            selected: selection.contains(file),
            onTap: () => onToggle(file),
            onLongPress: () => showFileDetails(context, file),
          ),
      ],
    );
  }
}

/// Headline card: how much space the installers occupy.
class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.summary});

  final ApkSummary summary;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Card(
      key: const Key('apk_total_card'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Space used by installers',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              ByteFormatter.format(summary.totalBytes),
              key: const Key('apk_total_bytes'),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${summary.fileCount} '
              '${summary.fileCount == 1 ? 'installer' : 'installers'} found',
              key: const Key('apk_count'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Installers are safe to remove once the app is installed. '
                    'Removing one does not uninstall the app.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
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

class _EmptyApks extends StatelessWidget {
  const _EmptyApks();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return ListView(
      key: const Key('apk_empty'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: <Widget>[
        const SizedBox(height: 60),
        Icon(
          Icons.check_circle_outline_rounded,
          size: 56,
          color: colors.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'No installer files found',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'There are no .apk files taking up space on this phone.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}
