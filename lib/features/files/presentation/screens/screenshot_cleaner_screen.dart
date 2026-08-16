import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/files/domain/delete_result.dart';
import 'package:mobile_cleaner/features/files/domain/file_selection.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/domain/screenshot_filter.dart';
import 'package:mobile_cleaner/features/files/domain/screenshot_summary.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/screenshot_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/delete_flow.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/files_status_views.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/scanned_file_tile.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/selection_action_bar.dart';

/// Screenshot cleaner: find screenshots and remove the ones no longer needed.
///
/// Deletion runs through the shared Review, Confirm, Delete, Result flow, so
/// nothing is removed without an explicit in-app confirmation.
class ScreenshotCleanerScreen extends ConsumerStatefulWidget {
  const ScreenshotCleanerScreen({super.key});

  @override
  ConsumerState<ScreenshotCleanerScreen> createState() =>
      _ScreenshotCleanerScreenState();
}

class _ScreenshotCleanerScreenState
    extends ConsumerState<ScreenshotCleanerScreen> {
  ScreenshotGroup _group = ScreenshotGroup.defaultGroup;
  FileSelection _selection = const FileSelection.empty();

  /// Switches group, then prunes selections that fall outside the new list so
  /// the action bar can never act on a hidden file.
  Future<void> _selectGroup(ScreenshotGroup group) async {
    setState(() => _group = group);
    if (_selection.isEmpty) {
      return;
    }

    final ScreenshotSummary next = await ref.read(
      screenshotSummaryProvider(group).future,
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
      ref.invalidate(screenshotScanProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<ScreenshotSummary> summary = ref.watch(
      screenshotSummaryProvider(_group),
    );
    final bool selecting = _selection.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        leading: selecting
            ? IconButton(
                key: const Key('screenshot_cancel_selection'),
                tooltip: 'Cancel selection',
                onPressed: _clearSelection,
                icon: const Icon(Icons.close_rounded),
              )
            : null,
        title: Text(
          selecting ? '${_selection.count} selected' : 'Screenshots',
          key: const Key('screenshot_title'),
        ),
        actions: <Widget>[
          if (!selecting)
            IconButton(
              key: const Key('screenshot_rescan'),
              tooltip: 'Rescan',
              onPressed: () => ref.invalidate(screenshotScanProvider),
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
            onRetry: () => ref.invalidate(screenshotScanProvider),
            onPermissions: () => context.push(AppRoutes.permissions),
          ),
          data: (ScreenshotSummary data) => Column(
            children: <Widget>[
              _GroupBar(
                selected: _group,
                onSelected: (ScreenshotGroup value) => _selectGroup(value),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(screenshotScanProvider);
                    await ref.read(screenshotScanProvider.future);
                  },
                  child: data.isEmpty
                      ? _EmptyScreenshots(group: _group)
                      : _ScreenshotList(
                          summary: data,
                          selection: _selection,
                          onToggle: _toggle,
                          onToggleAll: () => _toggleAll(data.files),
                        ),
                ),
              ),
              // In the body, below the Expanded list, so it shares the Column
              // rather than competing for the Scaffold's bottom slot.
              if (selecting)
                SelectionActionBar(
                  selection: _selection,
                  onClear: _clearSelection,
                  onDelete: _deleteSelected,
                  deletableCount: _selection.deletableCount,
                  barKey: const Key('screenshot_selection_bar'),
                  countKey: const Key('screenshot_selection_count'),
                  bytesKey: const Key('screenshot_selection_bytes'),
                  clearKey: const Key('screenshot_selection_clear'),
                  deleteKey: const Key('screenshot_selection_delete'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Group chips: All screenshots, 30+ days, 90+ days.
class _GroupBar extends StatelessWidget {
  const _GroupBar({required this.selected, required this.onSelected});

  final ScreenshotGroup selected;
  final ValueChanged<ScreenshotGroup> onSelected;

  @override
  Widget build(BuildContext context) {
    // Horizontally scrollable: three chips can overflow a narrow phone.
    return SizedBox(
      height: 52,
      child: ListView(
        key: const Key('screenshot_group_bar'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        children: <Widget>[
          for (final ScreenshotGroup option in ScreenshotGroup.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: Key('screenshot_group_${option.name}'),
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

class _ScreenshotList extends StatelessWidget {
  const _ScreenshotList({
    required this.summary,
    required this.selection,
    required this.onToggle,
    required this.onToggleAll,
  });

  final ScreenshotSummary summary;
  final FileSelection selection;
  final ValueChanged<ScannedFile> onToggle;
  final VoidCallback onToggleAll;

  @override
  Widget build(BuildContext context) {
    final bool allSelected = selection.containsAll(summary.files);

    // Lazily built. A plain `ListView(children: ...)` constructs every row up
    // front, so a single tap rebuilt up to 1000 rows, each re-establishing a
    // thumbnail provider and its platform-channel decode. That blocked the UI
    // thread long enough to look like a freeze: the tap registered and the
    // header updated, then nothing else responded.
    //
    // `ListView.builder` only builds what is on screen, so a rebuild costs a
    // handful of rows regardless of library size.
    const int headerCount = 2;

    return ListView.builder(
      key: const Key('screenshot_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
      itemCount: summary.files.length + headerCount,
      itemBuilder: (BuildContext context, int index) {
        if (index == 0) {
          return _TotalCard(summary: summary);
        }
        if (index == 1) {
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Newest first',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  key: const Key('screenshot_select_all'),
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
          );
        }

        final ScannedFile file = summary.files[index - headerCount];
        return ScannedFileTile(
          file: file,
          selectionMode: true,
          selected: selection.contains(file),
          onTap: () => onToggle(file),
          onLongPress: () => showFileDetails(context, file),
        );
      },
    );
  }
}

/// Headline: the count and total size the phase requires.
class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.summary});

  final ScreenshotSummary summary;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Card(
      key: const Key('screenshot_total_card'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Screenshots',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${summary.fileCount}',
                    key: const Key('screenshot_count'),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colors.primary,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  'Total size',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  ByteFormatter.format(summary.totalBytes),
                  key: const Key('screenshot_total_bytes'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
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

class _EmptyScreenshots extends StatelessWidget {
  const _EmptyScreenshots({required this.group});

  final ScreenshotGroup group;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return ListView(
      key: const Key('screenshot_empty'),
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
          group == ScreenshotGroup.all
              ? 'No screenshots found'
              : 'No screenshots ${group.description.toLowerCase()}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Nothing here is taking up space. Try a different range.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}
