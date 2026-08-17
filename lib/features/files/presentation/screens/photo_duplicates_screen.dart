import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/core/ui/haptics.dart';
import 'package:mobile_cleaner/core/ui/responsive.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/core/utils/date_formatter.dart';
import 'package:mobile_cleaner/features/files/domain/delete_result.dart';
import 'package:mobile_cleaner/features/files/domain/duplicate_group.dart';
import 'package:mobile_cleaner/features/files/domain/duplicate_keep_selection.dart';
import 'package:mobile_cleaner/features/files/domain/file_selection.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/photo_duplicates_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/delete_flow.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/file_thumbnail.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/files_status_views.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/scanned_file_tile.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/selection_action_bar.dart';

/// Duplicate Photos: the Phase 17 duplicate engine, images only.
///
/// Copies are shown side by side as pictures rather than as file rows, because
/// the only question worth asking about two identical photos is *which one do
/// I keep*, and that is answered by looking at them.
///
/// One copy of every set is always kept. The keeper is chosen by the user and
/// defaults to the oldest copy; it can never be selected for deletion, so the
/// tool cannot be used to erase a photo entirely.
class PhotoDuplicatesScreen extends ConsumerStatefulWidget {
  const PhotoDuplicatesScreen({super.key});

  @override
  ConsumerState<PhotoDuplicatesScreen> createState() =>
      _PhotoDuplicatesScreenState();
}

class _PhotoDuplicatesScreenState
    extends ConsumerState<PhotoDuplicatesScreen> {
  FileSelection _selection = const FileSelection.empty();
  DuplicateKeepSelection _keep = const DuplicateKeepSelection.empty();

  void _toggle(DuplicateGroup group, ScannedFile file) {
    if (_keep.isKept(group, file)) {
      return;
    }
    setState(() => _selection = _selection.toggle(file));
  }

  /// Switches the kept copy, and drops it from the selection in the same
  /// frame so a photo can never be both kept and queued for deletion.
  void _setKeeper(DuplicateGroup group, ScannedFile file) {
    setState(() {
      _keep = _keep.keep(group, file);
      _selection = _selection.deselectAll(<ScannedFile>[file]);
    });
  }

  void _toggleGroup(DuplicateGroup group) {
    final List<ScannedFile> removable = _keep.removable(group);
    setState(() {
      _selection = _selection.containsAll(removable)
          ? _selection.deselectAll(removable)
          : _selection.selectAll(removable);
    });
  }

  void _toggleAll(DuplicateScanResult result) {
    final List<ScannedFile> removable = _keep.removableAcross(result.groups);
    setState(() {
      _selection = _selection.containsAll(removable)
          ? _selection.deselectAll(removable)
          : _selection.selectAll(removable);
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
      ref.invalidate(photoDuplicateScanProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<DuplicateScanResult> duplicates = ref.watch(
      photoDuplicatesProvider,
    );
    final bool selecting = _selection.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        leading: selecting
            ? IconButton(
                key: const Key('photo_duplicates_cancel_selection'),
                tooltip: 'Cancel selection',
                onPressed: _clearSelection,
                icon: const Icon(Icons.close_rounded),
              )
            : null,
        title: Text(
          selecting ? '${_selection.count} selected' : 'Duplicate Photos',
          key: const Key('photo_duplicates_title'),
        ),
        actions: <Widget>[
          if (!selecting)
            IconButton(
              key: const Key('photo_duplicates_rescan'),
              tooltip: 'Rescan',
              onPressed: () => ref.invalidate(photoDuplicateScanProvider),
              icon: const Icon(Icons.refresh_rounded),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: duplicates.when(
          loading: () => const _ComparingView(),
          error: (Object error, StackTrace stackTrace) => FilesErrorView(
            error: error,
            onRetry: () => ref.invalidate(photoDuplicateScanProvider),
            onPermissions: () => context.push(AppRoutes.permissions),
          ),
          data: (DuplicateScanResult result) => Column(
            children: <Widget>[
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(photoDuplicateScanProvider);
                    await ref.read(photoDuplicatesProvider.future);
                  },
                  child: result.isEmpty
                      ? const _NoPhotoDuplicates()
                      : _PhotoGroupList(
                          result: result,
                          selection: _selection,
                          keep: _keep,
                          onToggle: _toggle,
                          onKeep: _setKeeper,
                          onToggleGroup: _toggleGroup,
                          onToggleAll: () => _toggleAll(result),
                        ),
                ),
              ),
              // In the body Column, below the Expanded list, never in
              // Scaffold.bottomNavigationBar.
              if (selecting)
                SelectionActionBar(
                  selection: _selection,
                  onClear: _clearSelection,
                  onDelete: _deleteSelected,
                  deletableCount: _selection.deletableCount,
                  barKey: const Key('photo_duplicates_selection_bar'),
                  countKey: const Key('photo_duplicates_selection_count'),
                  bytesKey: const Key('photo_duplicates_selection_bytes'),
                  clearKey: const Key('photo_duplicates_selection_clear'),
                  deleteKey: const Key('photo_duplicates_selection_delete'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoGroupList extends StatelessWidget {
  const _PhotoGroupList({
    required this.result,
    required this.selection,
    required this.keep,
    required this.onToggle,
    required this.onKeep,
    required this.onToggleGroup,
    required this.onToggleAll,
  });

  final DuplicateScanResult result;
  final FileSelection selection;
  final DuplicateKeepSelection keep;
  final void Function(DuplicateGroup, ScannedFile) onToggle;
  final void Function(DuplicateGroup, ScannedFile) onKeep;
  final ValueChanged<DuplicateGroup> onToggleGroup;
  final VoidCallback onToggleAll;

  @override
  Widget build(BuildContext context) {
    final List<ScannedFile> removable = keep.removableAcross(result.groups);
    final bool allSelected = selection.containsAll(removable);

    // Lazily built: a group holds several decoded thumbnails, so building
    // every group up front would stall the UI thread on a large library.
    const int headerCount = 2;

    return ListView.builder(
      key: const Key('photo_duplicates_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
      itemCount: result.groups.length + headerCount,
      itemBuilder: (BuildContext context, int index) {
        if (index == 0) {
          return _TotalCard(result: result, keep: keep);
        }
        if (index == 1) {
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Biggest savings first',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  key: const Key('photo_duplicates_select_all'),
                  onPressed: onToggleAll,
                  icon: Icon(
                    allSelected
                        ? Icons.remove_done_rounded
                        : Icons.done_all_rounded,
                    size: 18,
                  ),
                  label: Text(allSelected ? 'Clear all' : 'Select copies'),
                ),
              ],
            ),
          );
        }

        final DuplicateGroup group = result.groups[index - headerCount];
        return _PhotoGroupCard(
          group: group,
          selection: selection,
          keep: keep,
          onToggle: onToggle,
          onKeep: onKeep,
          onToggleGroup: () => onToggleGroup(group),
        );
      },
    );
  }
}

/// One duplicate set, shown as pictures so the user can compare copies.
class _PhotoGroupCard extends StatelessWidget {
  const _PhotoGroupCard({
    required this.group,
    required this.selection,
    required this.keep,
    required this.onToggle,
    required this.onKeep,
    required this.onToggleGroup,
  });

  final DuplicateGroup group;
  final FileSelection selection;
  final DuplicateKeepSelection keep;
  final void Function(DuplicateGroup, ScannedFile) onToggle;
  final void Function(DuplicateGroup, ScannedFile) onKeep;
  final VoidCallback onToggleGroup;

  /// Width of one photo cell, including its caption.
  static const double _cellWidth = 132;

  /// Height of the horizontal strip: thumbnail, caption, keep control.
  static const double _stripHeight = 232;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final List<ScannedFile> removable = keep.removable(group);
    final bool allSelected = selection.containsAll(removable);

    return Card(
      key: Key('photo_group_${group.hash}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${group.copyCount} identical photos · '
                    '${ByteFormatter.format(group.fileBytes)} each',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'save ${ByteFormatter.format(group.reclaimableBytes)}',
                  key: Key('photo_group_save_${group.hash}'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Tap Keep on the copy you want to keep. The rest can go.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            // Copies sit side by side so they can be compared at a glance.
            SizedBox(
              // Cells carry several caption lines, so this is the layout most
              // sensitive to a larger system font.
              height: Responsive.photoStripHeight(context, _stripHeight),
              child: ListView.builder(
                key: Key('photo_group_strip_${group.hash}'),
                scrollDirection: Axis.horizontal,
                itemCount: group.copyCount,
                itemBuilder: (BuildContext context, int index) {
                  final ScannedFile file = group.files[index];
                  return SizedBox(
                    width: _cellWidth,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: _CopyCell(
                        file: file,
                        kept: keep.isKept(group, file),
                        selected: selection.contains(file),
                        onTap: () => onToggle(group, file),
                        onKeep: () => onKeep(group, file),
                        onDetails: () => showFileDetails(context, file),
                      ),
                    ),
                  );
                },
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: Key('photo_group_select_${group.hash}'),
                onPressed: onToggleGroup,
                icon: Icon(
                  allSelected
                      ? Icons.remove_done_rounded
                      : Icons.done_all_rounded,
                  size: 18,
                ),
                label: Text(
                  allSelected
                      ? 'Clear this set'
                      : 'Select ${removable.length} extra '
                            '${removable.length == 1 ? 'copy' : 'copies'}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One copy: the picture, what marks it out, and its keep control.
class _CopyCell extends StatelessWidget {
  const _CopyCell({
    required this.file,
    required this.kept,
    required this.selected,
    required this.onTap,
    required this.onKeep,
    required this.onDetails,
  });

  final ScannedFile file;
  final bool kept;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onKeep;
  final VoidCallback onDetails;

  static const double _thumbSize = 118;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color border = kept
        ? colors.primary
        : selected
        ? colors.error
        : colors.outlineVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Semantics(
          // An image-only control is meaningless to a screen reader without
          // this: it announces the file, whether it is kept, and whether it
          // is currently marked for removal.
          label: file.name,
          selected: selected,
          button: true,
          child: GestureDetector(
          key: Key('photo_copy_${file.id}'),
          // Always hit-testable. A tap on the kept copy is ignored upstream
          // rather than being dropped here, so the cell never becomes a dead
          // region the user cannot even long-press for details.
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Haptics.selection();
            onTap();
          },
          onLongPress: onDetails,
          child: Container(
            width: _thumbSize,
            height: _thumbSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: border,
                width: kept || selected ? 3 : 1,
              ),
            ),
            child: Stack(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(3),
                  child: FileThumbnail(file: file, size: _thumbSize - 8),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: _CornerBadge(kept: kept, selected: selected),
                ),
              ],
            ),
          ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          file.name,
          key: Key('photo_copy_name_${file.id}'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        Text(
          DateFormatter.relative(file.dateModified),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        Text(
          file.folderName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        if (kept)
          Row(
            children: <Widget>[
              Icon(Icons.lock_outline_rounded, size: 14, color: colors.primary),
              const SizedBox(width: 4),
              Text(
                'Kept',
                key: Key('photo_copy_kept_${file.id}'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          )
        else
          SizedBox(
            height: Responsive.compactButtonHeight(context),
            child: TextButton(
              key: Key('photo_copy_keep_${file.id}'),
              onPressed: onKeep,
              style: TextButton.styleFrom(
                // Height only: a minimum width here could force an infinite
                // width inside a horizontal list.
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Keep this'),
            ),
          ),
      ],
    );
  }
}

/// Corner marker: locked when kept, ticked when queued for deletion.
class _CornerBadge extends StatelessWidget {
  const _CornerBadge({required this.kept, required this.selected});

  final bool kept;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    if (!kept && !selected) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: kept ? colors.primary : colors.error,
        shape: BoxShape.circle,
      ),
      child: Icon(
        kept ? Icons.lock_rounded : Icons.check_rounded,
        size: 14,
        color: kept ? colors.onPrimary : colors.onError,
      ),
    );
  }
}

/// Headline: what a full clean-up of duplicate photos would recover.
class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.result, required this.keep});

  final DuplicateScanResult result;
  final DuplicateKeepSelection keep;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final int reclaimable = keep.reclaimableBytes(result.groups);

    return Card(
      key: const Key('photo_duplicates_total_card'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Recoverable by removing extra copies',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              ByteFormatter.format(reclaimable),
              key: const Key('photo_duplicates_total_bytes'),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${result.duplicateCount} extra '
              '${result.duplicateCount == 1 ? 'photo' : 'photos'} across '
              '${result.groupCount} '
              '${result.groupCount == 1 ? 'set' : 'sets'}',
              key: const Key('photo_duplicates_count'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Icon(
                  Icons.verified_outlined,
                  size: 15,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Matched byte for byte. One photo of each set is always '
                    'kept.',
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

/// Hashing takes a moment, so explain what is happening.
class _ComparingView extends StatelessWidget {
  const _ComparingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('photo_duplicates_scanning'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: 18),
          Text(
            'Comparing photos…',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Only photos of matching size are read.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoPhotoDuplicates extends StatelessWidget {
  const _NoPhotoDuplicates();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return ListView(
      key: const Key('photo_duplicates_empty'),
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
          'No duplicate photos',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'No two pictures on this phone are byte for byte identical.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}
