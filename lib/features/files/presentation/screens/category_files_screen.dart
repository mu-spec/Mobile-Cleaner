import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/files/domain/delete_result.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_selection.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/file_scan_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/file_category_card.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/files_status_views.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/delete_flow.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/scanned_file_tile.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/selection_action_bar.dart';

/// Full, sortable, searchable list of the files inside one category.
class CategoryFilesScreen extends ConsumerStatefulWidget {
  const CategoryFilesScreen({required this.category, super.key});

  final FileCategory category;

  @override
  ConsumerState<CategoryFilesScreen> createState() =>
      _CategoryFilesScreenState();
}

class _CategoryFilesScreenState extends ConsumerState<CategoryFilesScreen> {
  final TextEditingController _searchController = TextEditingController();

  // Sort and search are per-visit UI state, so they live in the widget.
  FileListSort _sort = FileListSort.largest;
  String _query = '';
  bool _searching = false;
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

  /// Runs the shared Phase 12 flow, then drops whatever really went.
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
      ref.invalidate(fileScanProvider);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _closeSearch() {
    _searchController.clear();
    setState(() {
      _query = '';
      _searching = false;
    });
  }

  List<ScannedFile> _visibleFiles(List<ScannedFile> source) {
    final List<ScannedFile> files = List<ScannedFile>.of(source)
      ..sort(FileScanResult.compareFiles(_sort));
    final String needle = _query.trim().toLowerCase();
    if (needle.isEmpty) {
      return files;
    }
    return files
        .where((ScannedFile file) => file.name.toLowerCase().contains(needle))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<ScannedFile>> files = ref.watch(
      categoryFilesProvider(widget.category),
    );

    return Scaffold(
      appBar: AppBar(
        leading: _selection.isNotEmpty
            ? IconButton(
                key: const Key('category_cancel_selection'),
                tooltip: 'Cancel selection',
                onPressed: _clearSelection,
                icon: const Icon(Icons.close_rounded),
              )
            : null,
        title: _selection.isNotEmpty
            ? Text(
                '${_selection.count} selected',
                key: const Key('category_title'),
              )
            : _searching
            ? TextField(
                key: const Key('category_search_field'),
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search files',
                  border: InputBorder.none,
                ),
                onChanged: (String value) => setState(() => _query = value),
              )
            : Text(widget.category.label),
        actions: <Widget>[
          if (_selection.isNotEmpty)
            const SizedBox.shrink()
          else if (_searching)
            IconButton(
              key: const Key('category_search_close'),
              tooltip: 'Close search',
              onPressed: _closeSearch,
              icon: const Icon(Icons.close_rounded),
            )
          else ...<Widget>[
            IconButton(
              key: const Key('category_search_button'),
              tooltip: 'Search',
              onPressed: () => setState(() => _searching = true),
              icon: const Icon(Icons.search_rounded),
            ),
            PopupMenuButton<FileListSort>(
              key: const Key('category_sort_button'),
              tooltip: 'Sort',
              icon: const Icon(Icons.sort_rounded),
              initialValue: _sort,
              onSelected: (FileListSort value) =>
                  setState(() => _sort = value),
              itemBuilder: (BuildContext context) =>
                  <PopupMenuEntry<FileListSort>>[
                    for (final FileListSort option in FileListSort.values)
                      PopupMenuItem<FileListSort>(
                        key: Key('sort_option_${option.name}'),
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
          ],
        ],
      ),
      body: SafeArea(
        child: files.when(
          loading: () => const FilesScanningView(),
          error: (Object error, StackTrace stackTrace) => FilesErrorView(
            error: error,
            onRetry: () => ref.invalidate(fileScanProvider),
            onPermissions: () => context.push(AppRoutes.permissions),
          ),
          data: (List<ScannedFile> allFiles) {
            final List<ScannedFile> items = _visibleFiles(allFiles);
            if (items.isEmpty) {
              return _EmptyCategory(
                category: widget.category,
                query: _query,
                onClearSearch: _closeSearch,
              );
            }

            final int totalBytes = items.fold<int>(
              0,
              (int sum, ScannedFile file) => sum + file.sizeBytes,
            );

            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(fileScanProvider);
                await ref.read(fileScanProvider.future);
              },
              child: Column(
                children: <Widget>[
                  _CategoryHeader(
                    category: widget.category,
                    fileCount: items.length,
                    totalBytes: totalBytes,
                    sort: _sort,
                  ),
                  _SortBar(
                    selected: _sort,
                    onSelected: (FileListSort value) =>
                        setState(() => _sort = value),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: TextButton.icon(
                        key: const Key('category_select_all'),
                        onPressed: () => _toggleAll(items),
                        icon: Icon(
                          _selection.containsAll(items)
                              ? Icons.remove_done_rounded
                              : Icons.done_all_rounded,
                          size: 18,
                        ),
                        label: Text(
                          _selection.containsAll(items)
                              ? 'Clear all'
                              : 'Select all',
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      key: Key('category_list_${widget.category.key}'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      // Extra room while selecting so the action bar never
                      // covers the last row.
                      padding: EdgeInsets.fromLTRB(
                        16,
                        4,
                        16,
                        _selection.isEmpty ? 28 : 104,
                      ),
                      itemCount: items.length,
                      separatorBuilder:
                          (BuildContext context, int index) =>
                              const Divider(height: 1),
                      itemBuilder: (BuildContext context, int index) {
                        final ScannedFile file = items[index];
                        return ScannedFileTile(
                          file: file,
                          selectionMode: true,
                          selected: _selection.contains(file),
                          onTap: () => _toggle(file),
                          onLongPress: () => showFileDetails(context, file),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: _selection.isEmpty
          ? null
          : SelectionActionBar(
              selection: _selection,
              onClear: _clearSelection,
              onDelete: _deleteSelected,
              deletableCount: _selection.deletableCount,
              barKey: const Key('category_selection_bar'),
              countKey: const Key('category_selection_count'),
              bytesKey: const Key('category_selection_bytes'),
              clearKey: const Key('category_selection_clear'),
              deleteKey: const Key('category_selection_delete'),
            ),
    );
  }
}

/// Horizontal row of sort chips, so all five orders are one tap away.
class _SortBar extends StatelessWidget {
  const _SortBar({required this.selected, required this.onSelected});

  final FileListSort selected;
  final ValueChanged<FileListSort> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        key: const Key('sort_bar'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: <Widget>[
          for (final FileListSort option in FileListSort.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: Key('sort_chip_${option.name}'),
                label: Text(option.shortLabel),
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

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({
    required this.category,
    required this.fileCount,
    required this.totalBytes,
    required this.sort,
  });

  final FileCategory category;
  final int fileCount;
  final int totalBytes;
  final FileListSort sort;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color accent = colorForCategory(category);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      color: accent.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '$fileCount ${fileCount == 1 ? 'file' : 'files'} · '
            '${ByteFormatter.format(totalBytes)}',
            key: Key('category_header_${category.key}'),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(
            sort.label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _EmptyCategory extends StatelessWidget {
  const _EmptyCategory({
    required this.category,
    required this.query,
    required this.onClearSearch,
  });

  final FileCategory category;
  final String query;
  final VoidCallback onClearSearch;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool filtered = query.trim().isNotEmpty;

    return Center(
      key: Key('category_empty_${category.key}'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              filtered ? Icons.search_off_rounded : iconForCategory(category),
              size: 52,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              filtered ? 'No files match "$query"' : category.emptyMessage,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              filtered ? 'Try a different search.' : category.description,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            if (filtered) ...<Widget>[
              const SizedBox(height: 14),
              TextButton.icon(
                key: const Key('category_clear_search'),
                onPressed: onClearSearch,
                icon: const Icon(Icons.close_rounded),
                label: const Text('Clear search'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
