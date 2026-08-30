import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/core/utils/duration_formatter.dart';
import 'package:mobile_cleaner/features/files/domain/delete_result.dart';
import 'package:mobile_cleaner/features/files/domain/file_selection.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/domain/video_sort.dart';
import 'package:mobile_cleaner/features/files/domain/video_summary.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/videos_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/delete_flow.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/files_status_views.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/photo_tool_ui.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/scanned_file_tile.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/selection_action_bar.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/video_tile.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Videos: the dedicated section for reviewing video files.
///
/// Video is usually the largest thing on a phone, so this section leads with
/// size and length rather than burying them. Deletion runs through the shared
/// Review, Confirm, Delete, Result flow, so nothing is removed without an
/// explicit in-app confirmation.
class VideosScreen extends ConsumerStatefulWidget {
  const VideosScreen({super.key});

  @override
  ConsumerState<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends ConsumerState<VideosScreen> {
  VideoSort _sort = VideoSort.defaultSort;
  FileSelection _selection = const FileSelection.empty();

  /// Re-sorting shows the same videos in a different order, so the selection
  /// is deliberately preserved: nothing left the list.
  void _selectSort(VideoSort sort) {
    setState(() => _sort = sort);
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
      ref.invalidate(videoScanProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<VideoSummary> summary = ref.watch(
      videoSummaryProvider(_sort),
    );
    final bool selecting = _selection.isNotEmpty;

    return Scaffold(
      backgroundColor: PhotoToolUi.background(context),
      appBar: AppBar(
        backgroundColor: PhotoToolUi.background(context),
        surfaceTintColor: Colors.transparent,
        leading: selecting
            ? IconButton(
                key: const Key('videos_cancel_selection'),
                tooltip: 'Cancel selection',
                onPressed: _clearSelection,
                icon: const Icon(Icons.close_rounded),
              )
            : null,
        title: Text(
          selecting ? '${_selection.count} selected' : 'Videos',
          key: const Key('videos_title'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: <Widget>[
          if (!selecting)
            IconButton(
              key: const Key('videos_rescan'),
              tooltip: 'Rescan',
              onPressed: () => ref.invalidate(videoScanProvider),
              style: IconButton.styleFrom(
                backgroundColor: PhotoToolUi.isDark(context)
                    ? const Color(0xFF182945)
                    : const Color(0xFFEAF2FF),
                foregroundColor: PhotoToolUi.primary(context),
                side: BorderSide(color: PhotoToolUi.border(context)),
              ),
              icon: const PhosphorIcon(PhosphorIconsRegular.arrowsClockwise),
            ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: selecting
          ? SelectionActionBar(
              selection: _selection,
              onClear: _clearSelection,
              onDelete: _deleteSelected,
              deletableCount: _selection.deletableCount,
              barKey: const Key('videos_selection_bar'),
              countKey: const Key('videos_selection_count'),
              bytesKey: const Key('videos_selection_bytes'),
              clearKey: const Key('videos_selection_clear'),
              deleteKey: const Key('videos_selection_delete'),
            )
          : null,
      body: SafeArea(
        child: summary.when(
          loading: () => const FilesScanningView(),
          error: (Object error, StackTrace stackTrace) => FilesErrorView(
            error: error,
            onRetry: () => ref.invalidate(videoScanProvider),
            onPermissions: () => context.push(AppRoutes.permissions),
          ),
          data: (VideoSummary data) => Column(
            children: <Widget>[
              _SortBar(selected: _sort, onSelected: _selectSort),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(videoScanProvider);
                    await ref.read(videoScanProvider.future);
                  },
                  child: data.isEmpty
                      ? const _NoVideos()
                      : _VideoList(
                          summary: data,
                          selection: _selection,
                          onToggle: _toggle,
                          onToggleAll: () => _toggleAll(data.videos),
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

/// Sort chips: Largest, Longest, Newest, Oldest.
class _SortBar extends StatelessWidget {
  const _SortBar({required this.selected, required this.onSelected});

  final VideoSort selected;
  final ValueChanged<VideoSort> onSelected;

  @override
  Widget build(BuildContext context) {
    final double textScale = MediaQuery.textScalerOf(context).scale(1);

    return Padding(
      key: const Key('videos_sort_bar'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final int columns =
              constraints.maxWidth >= 360 && textScale <= 1.3 ? 4 : 2;
          const double gap = 8;
          final double chipWidth =
              (constraints.maxWidth - gap * (columns - 1)) / columns;

          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: <Widget>[
              for (final VideoSort option in VideoSort.values)
                SizedBox(
                  width: chipWidth,
                  child: PhotoToolChoiceChip(
                    key: Key('video_sort_${option.name}'),
                    label: option.label,
                    selected: option == selected,
                    onSelected: () => onSelected(option),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _VideoList extends StatelessWidget {
  const _VideoList({
    required this.summary,
    required this.selection,
    required this.onToggle,
    required this.onToggleAll,
  });

  final VideoSummary summary;
  final FileSelection selection;
  final ValueChanged<ScannedFile> onToggle;
  final VoidCallback onToggleAll;

  @override
  Widget build(BuildContext context) {
    final bool allSelected = selection.containsAll(summary.videos);

    // Lazily built: a plain ListView constructs every row up front, which
    // decodes every thumbnail and blocks the UI thread on one tap.
    const int headerCount = 2;

    return ListView.builder(
      key: const Key('videos_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
      itemCount: summary.videos.length + headerCount,
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
                    summary.sort.description,
                    key: const Key('videos_sort_note'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  key: const Key('videos_select_all'),
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

        final ScannedFile file = summary.videos[index - headerCount];
        return PhotoToolFilePanel(
          child: VideoTile(
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

/// Headline: how much space and how much footage.
class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.summary});

  final VideoSummary summary;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final int unknown = summary.unknownDurationCount;
    final String unknownNoun = unknown == 1 ? 'video' : 'videos';

    return Card(
      key: const Key('videos_total_card'),
      color: PhotoToolUi.surface(context),
      surfaceTintColor: Colors.transparent,
      elevation: PhotoToolUi.isDark(context) ? 0 : 2,
      shadowColor: const Color(0xFF102B5B).withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: PhotoToolUi.border(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Space used by videos',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              ByteFormatter.format(summary.totalBytes),
              key: const Key('videos_total_bytes'),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: PhotoToolUi.orange(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${summary.videoCount} '
              '${summary.videoCount == 1 ? 'video' : 'videos'} · '
              '${DurationFormatter.formatLong(summary.totalDuration)}',
              key: const Key('videos_count'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            if (!summary.isEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                'Average ${ByteFormatter.format(summary.averageBytes)} each',
                key: const Key('videos_average'),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
            // Say so rather than quietly understating the total footage.
            if (summary.hasUnknownDurations) ...<Widget>[
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  PhosphorIcon(
                    PhosphorIconsDuotone.info,
                    size: 15,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$unknown $unknownNoun had no length recorded, so the '
                      'total is a minimum.',
                      key: const Key('videos_unknown_note'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NoVideos extends StatelessWidget {
  const _NoVideos();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return ListView(
      key: const Key('videos_empty'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: <Widget>[
        const SizedBox(height: 60),
        PhosphorIcon(
          PhosphorIconsDuotone.videoCameraSlash,
          size: 64,
          color: PhotoToolUi.primary(context),
          duotoneSecondaryColor: PhotoToolUi.orange(context),
          duotoneSecondaryOpacity: 0.9,
        ),
        const SizedBox(height: 16),
        Text(
          'No videos found',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Nothing in your video library is visible to this app.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}
