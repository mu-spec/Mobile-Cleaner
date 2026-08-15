import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/files/domain/download_age_filter.dart';
import 'package:mobile_cleaner/features/files/domain/downloads_summary.dart';
import 'package:mobile_cleaner/features/files/domain/file_selection.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/downloads_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/files_status_views.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/scanned_file_tile.dart';

/// Downloads cleaner: find stale downloads by age and select them in bulk.
///
/// Read-only in this phase. Selection is built here so a later phase can
/// attach a delete action without reworking the list.
class DownloadsCleanerScreen extends ConsumerStatefulWidget {
  const DownloadsCleanerScreen({super.key});

  @override
  ConsumerState<DownloadsCleanerScreen> createState() =>
      _DownloadsCleanerScreenState();
}

class _DownloadsCleanerScreenState
    extends ConsumerState<DownloadsCleanerScreen> {
  DownloadAgeFilter _filter = DownloadAgeFilter.defaultFilter;
  FileSelection _selection = const FileSelection.empty();

  /// Switches threshold, then prunes selections that fall outside the new
  /// list so the action bar can never act on a hidden file.
  Future<void> _selectFilter(DownloadAgeFilter filter) async {
    setState(() => _filter = filter);
    if (_selection.isEmpty) {
      return;
    }

    final DownloadsSummary next = await ref.read(
      downloadsSummaryProvider(filter).future,
    );
    if (!mounted) {
      return;
    }
    setState(() => _selection = _selection.retainWhereVisible(next.files));
  }

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

  @override
  Widget build(BuildContext context) {
    final AsyncValue<DownloadsSummary> summary = ref.watch(
      downloadsSummaryProvider(_filter),
    );
    final bool selecting = _selection.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        leading: selecting
            ? IconButton(
                key: const Key('downloads_cancel_selection'),
                tooltip: 'Cancel selection',
                onPressed: _clearSelection,
                icon: const Icon(Icons.close_rounded),
              )
            : null,
        title: Text(
          selecting ? '${_selection.count} selected' : 'Downloads Cleaner',
          key: const Key('downloads_title'),
        ),
        actions: <Widget>[
          if (!selecting)
            IconButton(
              key: const Key('downloads_rescan'),
              tooltip: 'Rescan',
              onPressed: () => ref.invalidate(downloadsScanProvider),
              icon: const Icon(Icons.refresh_rounded),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: summary.when(
          loading: () => const FilesScanningView(),
          error: (Object error, StackTrace stackTrace) => FilesErrorView(
            error: error,
            onRetry: () => ref.invalidate(downloadsScanProvider),
            onPermissions: () => context.push(AppRoutes.permissions),
          ),
          data: (DownloadsSummary data) {
            return Column(
              children: <Widget>[
                _AgeFilterBar(
                  selected: _filter,
                  onSelected: (DownloadAgeFilter value) => _selectFilter(value),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(downloadsScanProvider);
                      await ref.read(downloadsScanProvider.future);
                    },
                    child: data.isEmpty
                        ? _EmptyDownloads(filter: _filter)
                        : _DownloadsList(
                            summary: data,
                            selection: _selection,
                            onToggle: _toggle,
                            onToggleAll: () => _toggleAll(data.files),
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: selecting
          ? _SelectionBar(selection: _selection, onClear: _clearSelection)
          : null,
    );
  }
}

/// Age chips: 30+ days, 90+ days, 6+ months, 1+ year.
class _AgeFilterBar extends StatelessWidget {
  const _AgeFilterBar({required this.selected, required this.onSelected});

  final DownloadAgeFilter selected;
  final ValueChanged<DownloadAgeFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView(
        key: const Key('downloads_filter_bar'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        children: <Widget>[
          for (final DownloadAgeFilter option in DownloadAgeFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: Key('age_filter_${option.name}'),
                label: Text(option.label),
                selected: option == selected,
                onSelected: (_) => onSelected(option),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }
}

class _DownloadsList extends StatelessWidget {
  const _DownloadsList({
    required this.summary,
    required this.selection,
    required this.onToggle,
    required this.onToggleAll,
  });

  final DownloadsSummary summary;
  final FileSelection selection;
  final ValueChanged<ScannedFile> onToggle;
  final VoidCallback onToggleAll;

  @override
  Widget build(BuildContext context) {
    final bool allSelected = selection.containsAll(summary.files);

    return ListView(
      key: const Key('downloads_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
      children: <Widget>[
        _TotalCard(summary: summary),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Oldest first',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton.icon(
              key: const Key('downloads_select_all'),
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

/// Headline card: how much space the stale downloads occupy.
class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.summary});

  final DownloadsSummary summary;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Card(
      key: const Key('downloads_total_card'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Space used by old downloads',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              ByteFormatter.format(summary.totalBytes),
              key: const Key('downloads_total_bytes'),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${summary.fileCount} '
              '${summary.fileCount == 1 ? 'download' : 'downloads'} older than '
              '${summary.filter.threshold}',
              key: const Key('downloads_count'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom bar summarising the current multi-selection.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.selection, required this.onClear});

  final FileSelection selection;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Material(
      key: const Key('downloads_selection_bar'),
      color: colors.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      '${selection.count} selected',
                      key: const Key('selection_count'),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      ByteFormatter.format(selection.totalBytes),
                      key: const Key('selection_bytes'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                key: const Key('selection_clear'),
                onPressed: onClear,
                child: const Text('Clear'),
              ),
              const SizedBox(width: 4),
              // Deletion arrives in a later phase; the affordance is shown
              // disabled so the flow is visible but cannot act yet.
              FilledButton.icon(
                key: const Key('selection_delete'),
                onPressed: null,
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

class _EmptyDownloads extends StatelessWidget {
  const _EmptyDownloads({required this.filter});

  final DownloadAgeFilter filter;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return ListView(
      key: const Key('downloads_empty'),
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
          'No downloads older than ${filter.threshold}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Your Downloads folder is tidy. Try a shorter time range.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}
