import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/core/ui/responsive.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/files/domain/delete_result.dart';
import 'package:mobile_cleaner/features/files/domain/file_selection.dart';
import 'package:mobile_cleaner/features/files/domain/large_photo_filter.dart';
import 'package:mobile_cleaner/features/files/domain/large_photo_summary.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/large_photos_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/delete_flow.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/files_status_views.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/photo_tool_ui.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/scanned_file_tile.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/selection_action_bar.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Large Photos: find the images taking the most space.
///
/// Deletion runs through the shared Review, Confirm, Delete, Result flow, so
/// nothing is removed without an explicit in-app confirmation.
class LargePhotosScreen extends ConsumerStatefulWidget {
  const LargePhotosScreen({super.key});

  @override
  ConsumerState<LargePhotosScreen> createState() => _LargePhotosScreenState();
}

class _LargePhotosScreenState extends ConsumerState<LargePhotosScreen> {
  LargePhotoFilter _filter = LargePhotoFilter.defaultFilter;
  FileSelection _selection = const FileSelection.empty();

  /// Switches threshold, then prunes selections that fall outside the new
  /// list so the action bar can never act on a hidden photo.
  Future<void> _selectFilter(LargePhotoFilter filter) async {
    setState(() => _filter = filter);
    if (_selection.isEmpty) {
      return;
    }

    final LargePhotoSummary next = await ref.read(
      largePhotoSummaryProvider(filter).future,
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
      ref.invalidate(largePhotoScanProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<LargePhotoSummary> summary = ref.watch(
      largePhotoSummaryProvider(_filter),
    );
    final bool selecting = _selection.isNotEmpty;

    return Scaffold(
      backgroundColor: PhotoToolUi.background(context),
      appBar: AppBar(
        backgroundColor: PhotoToolUi.background(context),
        surfaceTintColor: Colors.transparent,
        leading: selecting
            ? IconButton(
                key: const Key('large_photos_cancel_selection'),
                tooltip: 'Cancel selection',
                onPressed: _clearSelection,
                icon: const Icon(Icons.close_rounded),
              )
            : null,
        title: Text(
          selecting ? '${_selection.count} selected' : 'Large Photos',
          key: const Key('large_photos_title'),
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
        ),
        actions: <Widget>[
          if (!selecting)
            PhotoToolActionButton(
              key: const Key('large_photos_rescan'),
              icon: Icons.refresh_rounded,
              tooltip: 'Rescan',
              onPressed: () => ref.invalidate(largePhotoScanProvider),
            ),
        ],
      ),
      bottomNavigationBar: selecting
          ? SelectionActionBar(
              selection: _selection,
              onClear: _clearSelection,
              onDelete: _deleteSelected,
              deletableCount: _selection.deletableCount,
              barKey: const Key('large_photos_selection_bar'),
              countKey: const Key('large_photos_selection_count'),
              bytesKey: const Key('large_photos_selection_bytes'),
              clearKey: const Key('large_photos_selection_clear'),
              deleteKey: const Key('large_photos_selection_delete'),
            )
          : null,
      body: SafeArea(
        child: summary.when(
          loading: () => const PhotoToolLoadingState(
            icon: PhosphorIconsDuotone.imageSquare,
            title: 'Measuring large photos…',
            description: 'Calculating real photo sizes safely on this device.',
          ),
          error: (Object error, StackTrace stackTrace) => FilesErrorView(
            error: error,
            onRetry: () => ref.invalidate(largePhotoScanProvider),
            onPermissions: () => context.push(AppRoutes.permissions),
          ),
          data: (LargePhotoSummary data) => Column(
            children: <Widget>[
              _FilterBar(
                selected: _filter,
                onSelected: (LargePhotoFilter value) => _selectFilter(value),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(largePhotoScanProvider);
                    await ref.read(largePhotoScanProvider.future);
                  },
                  child: data.isEmpty
                      ? _EmptyLargePhotos(filter: _filter)
                      : _LargePhotoList(
                          summary: data,
                          selection: _selection,
                          onToggle: _toggle,
                          onToggleAll: () => _toggleAll(data.files),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Threshold chips: 5 MB+, 10 MB+, 20 MB+.
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onSelected});

  final LargePhotoFilter selected;
  final ValueChanged<LargePhotoFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    // Horizontally scrollable: three chips can overflow a narrow phone.
    return SizedBox(
      // Grows with the user's text scale so chip labels are never clipped.
      height: Responsive.chipBarHeight(context),
      child: ListView(
        key: const Key('large_photos_filter_bar'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        children: <Widget>[
          for (final LargePhotoFilter option in LargePhotoFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: PhotoToolChoiceChip(
                key: Key('large_photo_filter_${option.name}'),
                label: option.label,
                selected: option == selected,
                onSelected: () => onSelected(option),
              ),
            ),
        ],
      ),
    );
  }
}

class _LargePhotoList extends StatelessWidget {
  const _LargePhotoList({
    required this.summary,
    required this.selection,
    required this.onToggle,
    required this.onToggleAll,
  });

  final LargePhotoSummary summary;
  final FileSelection selection;
  final ValueChanged<ScannedFile> onToggle;
  final VoidCallback onToggleAll;

  @override
  Widget build(BuildContext context) {
    final bool allSelected = selection.containsAll(summary.files);

    // Lazily built: a plain `ListView(children: ...)` constructs every row up
    // front, so one tap rebuilt the whole library and blocked the UI thread.
    const int headerCount = 2;

    return ListView.builder(
      key: const Key('large_photos_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
      itemCount: summary.files.length + headerCount,
      itemBuilder: (BuildContext context, int index) {
        if (index == 0) {
          return _TotalCard(summary: summary);
        }
        if (index == 1) {
          return PhotoToolSectionHeader(
            title: 'Space-heavy photos',
            subtitle: 'Largest first',
            icon: PhosphorIconsDuotone.imageSquare,
            trailing: TextButton.icon(
              key: const Key('large_photos_select_all'),
              onPressed: onToggleAll,
              icon: Icon(
                allSelected
                    ? Icons.remove_done_rounded
                    : Icons.done_all_rounded,
                size: 18,
              ),
              label: Text(allSelected ? 'Clear all' : 'Select all'),
            ),
          );
        }

        final ScannedFile file = summary.files[index - headerCount];
        return PhotoToolFilePanel(
          child: ScannedFileTile(
            file: file,
            selectionMode: true,
            selected: selection.contains(file),
            onTap: () => onToggle(file),
            onLongPress: () => showFileDetails(context, file),
          ),
        );
      },
    );
  }
}

/// Headline: how much space the large photos occupy.
class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.summary});

  final LargePhotoSummary summary;

  @override
  Widget build(BuildContext context) {
    final String description =
        '${summary.fileCount} '
        '${summary.fileCount == 1 ? 'photo' : 'photos'} over '
        '${summary.filter.threshold}';

    return PhotoToolSummaryCard(
      key: const Key('large_photos_total_card'),
      icon: PhosphorIconsDuotone.imageSquare,
      eyebrow: 'Photo storage',
      value: ByteFormatter.format(summary.totalBytes),
      valueKey: const Key('large_photos_total_bytes'),
      description: description,
      descriptionKey: const Key('large_photos_count'),
      note: summary.isEmpty
          ? null
          : PhotoToolHeroNote(
              key: const Key('large_photos_average'),
              icon: PhosphorIconsDuotone.gauge,
              text:
                  'Average ${ByteFormatter.format(summary.averageBytes)} per photo',
            ),
    );
  }
}

class _EmptyLargePhotos extends StatelessWidget {
  const _EmptyLargePhotos({required this.filter});

  final LargePhotoFilter filter;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('large_photos_empty'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: <Widget>[
        PhotoToolEmptyState(
          icon: PhosphorIconsDuotone.imageSquare,
          title: 'No photos over ${filter.threshold}',
          description:
              'Nothing in your library is that large. Try a smaller threshold.',
        ),
      ],
    );
  }
}
