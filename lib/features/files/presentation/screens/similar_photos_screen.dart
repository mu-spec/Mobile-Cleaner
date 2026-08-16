import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/core/utils/date_formatter.dart';
import 'package:mobile_cleaner/features/files/domain/delete_result.dart';
import 'package:mobile_cleaner/features/files/domain/duplicate_keep_selection.dart';
import 'package:mobile_cleaner/features/files/domain/file_selection.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/domain/similar_photo_group.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/similar_photos_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/delete_flow.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/file_thumbnail.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/files_status_views.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/scanned_file_tile.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/selection_action_bar.dart';

/// Similar Photos: shots that look alike without being byte-identical.
///
/// Deliberately more cautious than the duplicate tool. Exact duplicates are
/// interchangeable, so selecting every extra copy is safe. Similar photos are
/// **not** — one may be the sharp one, or the one where nobody blinked — so:
///
///  - nothing is ever pre-selected
///  - there is no global "select all"
///  - the keeper defaults to the first shot but the user is expected to look
///
/// One photo of every set is always kept, exactly as in the duplicate tool.
class SimilarPhotosScreen extends ConsumerStatefulWidget {
  const SimilarPhotosScreen({super.key});

  @override
  ConsumerState<SimilarPhotosScreen> createState() =>
      _SimilarPhotosScreenState();
}

class _SimilarPhotosScreenState extends ConsumerState<SimilarPhotosScreen> {
  SimilarityStrength _strength = SimilarityStrength.defaultStrength;
  FileSelection _selection = const FileSelection.empty();
  DuplicateKeepSelection _keep = const DuplicateKeepSelection.empty();

  /// Switching strength re-groups the same hashes, so nothing is decoded
  /// again. Selections are dropped because the groups they belonged to no
  /// longer exist in the same shape.
  void _selectStrength(SimilarityStrength strength) {
    setState(() {
      _strength = strength;
      _selection = _selection.clear();
      _keep = const DuplicateKeepSelection.empty();
    });
  }

  void _toggle(SimilarPhotoGroup group, ScannedFile file) {
    if (_keep.isKept(group, file)) {
      return;
    }
    setState(() => _selection = _selection.toggle(file));
  }

  void _setKeeper(SimilarPhotoGroup group, ScannedFile file) {
    setState(() {
      _keep = _keep.keep(group, file);
      _selection = _selection.deselectAll(<ScannedFile>[file]);
    });
  }

  /// Selects the extra shots of one set only.
  ///
  /// Per-set by design: there is no action that selects across every group,
  /// because "delete all similar photos" is exactly the operation a user
  /// regrets.
  void _toggleGroup(SimilarPhotoGroup group) {
    final List<ScannedFile> removable = _keep.removable(group);
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
      ref.invalidate(similarPhotoScanProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<SimilarPhotoScanResult> similar = ref.watch(
      similarPhotosProvider(_strength),
    );
    final bool selecting = _selection.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        leading: selecting
            ? IconButton(
                key: const Key('similar_photos_cancel_selection'),
                tooltip: 'Cancel selection',
                onPressed: _clearSelection,
                icon: const Icon(Icons.close_rounded),
              )
            : null,
        title: Text(
          selecting ? '${_selection.count} selected' : 'Similar Photos',
          key: const Key('similar_photos_title'),
        ),
        actions: <Widget>[
          if (!selecting)
            IconButton(
              key: const Key('similar_photos_rescan'),
              tooltip: 'Rescan',
              onPressed: () => ref.invalidate(similarPhotoScanProvider),
              icon: const Icon(Icons.refresh_rounded),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: similar.when(
          loading: () => const _AnalyzingView(),
          error: (Object error, StackTrace stackTrace) => FilesErrorView(
            error: error,
            onRetry: () => ref.invalidate(similarPhotoScanProvider),
            onPermissions: () => context.push(AppRoutes.permissions),
          ),
          data: (SimilarPhotoScanResult result) => Column(
            children: <Widget>[
              _StrengthBar(selected: _strength, onSelected: _selectStrength),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(similarPhotoScanProvider);
                    await ref.read(similarPhotosProvider(_strength).future);
                  },
                  child: result.isEmpty
                      ? _NoSimilarPhotos(strength: _strength)
                      : _SimilarGroupList(
                          result: result,
                          selection: _selection,
                          keep: _keep,
                          onToggle: _toggle,
                          onKeep: _setKeeper,
                          onToggleGroup: _toggleGroup,
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
                  barKey: const Key('similar_photos_selection_bar'),
                  countKey: const Key('similar_photos_selection_count'),
                  bytesKey: const Key('similar_photos_selection_bytes'),
                  clearKey: const Key('similar_photos_selection_clear'),
                  deleteKey: const Key('similar_photos_selection_delete'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Strength chips: Strict, Balanced, Relaxed.
class _StrengthBar extends StatelessWidget {
  const _StrengthBar({required this.selected, required this.onSelected});

  final SimilarityStrength selected;
  final ValueChanged<SimilarityStrength> onSelected;

  @override
  Widget build(BuildContext context) {
    // Horizontally scrollable: three chips can overflow a narrow phone.
    return SizedBox(
      height: 52,
      child: ListView(
        key: const Key('similar_photos_strength_bar'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        children: <Widget>[
          for (final SimilarityStrength option in SimilarityStrength.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: Key('similarity_${option.name}'),
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

class _SimilarGroupList extends StatelessWidget {
  const _SimilarGroupList({
    required this.result,
    required this.selection,
    required this.keep,
    required this.onToggle,
    required this.onKeep,
    required this.onToggleGroup,
  });

  final SimilarPhotoScanResult result;
  final FileSelection selection;
  final DuplicateKeepSelection keep;
  final void Function(SimilarPhotoGroup, ScannedFile) onToggle;
  final void Function(SimilarPhotoGroup, ScannedFile) onKeep;
  final ValueChanged<SimilarPhotoGroup> onToggleGroup;

  @override
  Widget build(BuildContext context) {
    // Lazily built: each group decodes several thumbnails, so building every
    // group up front would stall the UI thread.
    const int headerCount = 1;

    return ListView.builder(
      key: const Key('similar_photos_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
      itemCount: result.groups.length + headerCount,
      itemBuilder: (BuildContext context, int index) {
        if (index == 0) {
          return _TotalCard(result: result);
        }
        final SimilarPhotoGroup group = result.groups[index - headerCount];
        return _SimilarGroupCard(
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

/// One similar set, shown as pictures so the user can pick the best shot.
class _SimilarGroupCard extends StatelessWidget {
  const _SimilarGroupCard({
    required this.group,
    required this.selection,
    required this.keep,
    required this.onToggle,
    required this.onKeep,
    required this.onToggleGroup,
  });

  final SimilarPhotoGroup group;
  final FileSelection selection;
  final DuplicateKeepSelection keep;
  final void Function(SimilarPhotoGroup, ScannedFile) onToggle;
  final void Function(SimilarPhotoGroup, ScannedFile) onKeep;
  final VoidCallback onToggleGroup;

  static const double _cellWidth = 132;
  static const double _stripHeight = 232;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final List<ScannedFile> removable = keep.removable(group);
    final bool allSelected = selection.containsAll(removable);

    return Card(
      key: Key('similar_group_${group.key}'),
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
                    group.isBurst
                        ? '${group.photoCount} shots in a burst'
                        : '${group.photoCount} similar photos',
                    key: Key('similar_group_title_${group.key}'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'up to ${ByteFormatter.format(group.reclaimableBytes)}',
                  key: Key('similar_group_save_${group.key}'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'These look alike but are not identical. Compare them before '
              'removing any.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: _stripHeight,
              child: ListView.builder(
                key: Key('similar_group_strip_${group.key}'),
                scrollDirection: Axis.horizontal,
                itemCount: group.photoCount,
                itemBuilder: (BuildContext context, int index) {
                  final ScannedFile file = group.files[index];
                  return SizedBox(
                    width: _cellWidth,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: _ShotCell(
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
                key: Key('similar_group_select_${group.key}'),
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
                      : 'Select ${removable.length} other '
                            '${removable.length == 1 ? 'shot' : 'shots'}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One shot: the picture, what distinguishes it, and its keep control.
class _ShotCell extends StatelessWidget {
  const _ShotCell({
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
        GestureDetector(
          key: Key('similar_shot_${file.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
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
        const SizedBox(height: 4),
        Text(
          file.name,
          key: Key('similar_shot_name_${file.id}'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        // Size is shown here, unlike the duplicate tool, because similar shots
        // differ in size and that is a real reason to prefer one.
        Text(
          ByteFormatter.format(file.sizeBytes),
          key: Key('similar_shot_size_${file.id}'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        Text(
          DateFormatter.relative(file.dateModified),
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
                key: Key('similar_shot_kept_${file.id}'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          )
        else
          SizedBox(
            height: 30,
            child: TextButton(
              key: Key('similar_shot_keep_${file.id}'),
              onPressed: onKeep,
              style: TextButton.styleFrom(
                // Height only. A minimum width here would force an infinite
                // width inside the horizontal strip.
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

/// Headline: an upper bound, phrased as such.
class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.result});

  final SimilarPhotoScanResult result;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Card(
      key: const Key('similar_photos_total_card'),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Recoverable if you keep one of each',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              'up to ${ByteFormatter.format(result.reclaimableBytes)}',
              key: const Key('similar_photos_total_bytes'),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${result.extraPhotoCount} extra '
              '${result.extraPhotoCount == 1 ? 'shot' : 'shots'} across '
              '${result.groupCount} '
              '${result.groupCount == 1 ? 'set' : 'sets'}',
              key: const Key('similar_photos_count'),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Icon(
                  Icons.visibility_outlined,
                  size: 15,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Matched by appearance, not byte for byte. Nothing is '
                    'selected for you — check each shot first.',
                    key: const Key('similar_photos_caution'),
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

/// Decoding takes a moment, so say what is happening and that it is local.
class _AnalyzingView extends StatelessWidget {
  const _AnalyzingView();

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('similar_photos_analyzing'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: 18),
          Text(
            'Analyzing photos…',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Comparison happens on this device. Nothing is uploaded.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoSimilarPhotos extends StatelessWidget {
  const _NoSimilarPhotos({required this.strength});

  final SimilarityStrength strength;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return ListView(
      key: const Key('similar_photos_empty'),
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
          'No similar photos',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          strength == SimilarityStrength.relaxed
              ? 'Nothing in your library looks alike.'
              : 'Nothing matched at ${strength.label} strength. Try a wider '
                    'setting.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}
