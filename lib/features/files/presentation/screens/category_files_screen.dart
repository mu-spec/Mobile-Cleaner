import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_scan_result.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/file_scan_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/file_category_card.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/files_status_views.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/scanned_file_tile.dart';

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
        title: _searching
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
          if (_searching)
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
                        child: Text(option.label),
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
                  Expanded(
                    child: ListView.separated(
                      key: Key('category_list_${widget.category.key}'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                      itemCount: items.length,
                      separatorBuilder:
                          (BuildContext context, int index) =>
                              const Divider(height: 1),
                      itemBuilder: (BuildContext context, int index) =>
                          ScannedFileTile(file: items[index]),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
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
