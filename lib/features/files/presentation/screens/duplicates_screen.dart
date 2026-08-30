import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/core/utils/date_formatter.dart';
import 'package:mobile_cleaner/features/files/domain/delete_result.dart';
import 'package:mobile_cleaner/features/files/domain/duplicate_group.dart';
import 'package:mobile_cleaner/features/files/domain/file_selection.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/duplicates_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/delete_flow.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/files_status_views.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/photo_tool_ui.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/scanned_file_tile.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/selection_action_bar.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Duplicate files: byte-identical copies, proven by content hash.
///
/// The first copy in each group is shown as the one to keep and cannot be
/// selected. That is the core safety rule: the tool can never be used to
/// delete every copy of a file, which would be data loss rather than cleaning.
class DuplicatesScreen extends ConsumerStatefulWidget {
  const DuplicatesScreen({super.key});

  @override
  ConsumerState<DuplicatesScreen> createState() => _DuplicatesScreenState();
}

class _DuplicatesScreenState extends ConsumerState<DuplicatesScreen> {
  FileSelection _selection = const FileSelection.empty();

  void _toggle(ScannedFile file) {
    setState(() => _selection = _selection.toggle(file));
  }

  /// Selects every removable copy, always leaving one of each group behind.
  void _selectAllDuplicates(DuplicateScanResult result) {
    final List<ScannedFile> removable = result.allDuplicates;
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
      ref.invalidate(duplicateScanProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<DuplicateScanResult> duplicates = ref.watch(
      duplicatesProvider,
    );
    final bool selecting = _selection.isNotEmpty;

    return Scaffold(
      backgroundColor: PhotoToolUi.background(context),
      appBar: AppBar(
        backgroundColor: PhotoToolUi.background(context),
        surfaceTintColor: Colors.transparent,
        leading: selecting
            ? IconButton(
                key: const Key('duplicates_cancel_selection'),
                tooltip: 'Cancel selection',
                onPressed: _clearSelection,
                icon: const Icon(Icons.close_rounded),
              )
            : null,
        title: Text(
          selecting ? '${_selection.count} selected' : 'Duplicates',
          key: const Key('duplicates_title'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: <Widget>[
          if (!selecting)
            IconButton(
              key: const Key('duplicates_rescan'),
              tooltip: 'Rescan',
              onPressed: () => ref.invalidate(duplicateScanProvider),
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
              barKey: const Key('duplicates_selection_bar'),
              countKey: const Key('duplicates_selection_count'),
              bytesKey: const Key('duplicates_selection_bytes'),
              clearKey: const Key('duplicates_selection_clear'),
              deleteKey: const Key('duplicates_selection_delete'),
            )
          : null,
      body: SafeArea(
        child: duplicates.when(
          loading: () => const _HashingView(),
          error: (Object error, StackTrace stackTrace) => FilesErrorView(
            error: error,
            onRetry: () => ref.invalidate(duplicateScanProvider),
            onPermissions: () => context.push(AppRoutes.permissions),
          ),
          data: (DuplicateScanResult result) => Column(
            children: <Widget>[
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(duplicateScanProvider);
                    await ref.read(duplicatesProvider.future);
                  },
                  child: result.isEmpty
                      ? const _NoDuplicates()
                      : _DuplicateList(
                          result: result,
                          selection: _selection,
                          onToggle: _toggle,
                          onSelectAll: () => _selectAllDuplicates(result),
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

class _DuplicateList extends StatelessWidget {
  const _DuplicateList({
    required this.result,
    required this.selection,
    required this.onToggle,
    required this.onSelectAll,
  });

  final DuplicateScanResult result;
  final FileSelection selection;
  final ValueChanged<ScannedFile> onToggle;
  final VoidCallback onSelectAll;

  @override
  Widget build(BuildContext context) {
    final bool allSelected = selection.containsAll(result.allDuplicates);

    // Lazily built, so one tap does not rebuild every group.
    const int headerCount = 2;

    return ListView.builder(
      key: const Key('duplicates_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
      itemCount: result.groups.length + headerCount,
      itemBuilder: (BuildContext context, int index) {
        if (index == 0) {
          return _TotalCard(result: result);
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
                  key: const Key('duplicates_select_all'),
                  onPressed: onSelectAll,
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

        return _GroupCard(
          group: result.groups[index - headerCount],
          selection: selection,
          onToggle: onToggle,
        );
      },
    );
  }
}

/// One duplicate set: the kept copy, then each removable copy.
class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.selection,
    required this.onToggle,
  });

  final DuplicateGroup group;
  final FileSelection selection;
  final ValueChanged<ScannedFile> onToggle;

  @override
  Widget build(BuildContext context) {
    final ScannedFile? original = group.original;

    return Card(
      key: Key('duplicate_group_${group.hash}'),
      margin: const EdgeInsets.only(bottom: 12),
      color: PhotoToolUi.surface(context),
      surfaceTintColor: Colors.transparent,
      elevation: PhotoToolUi.isDark(context) ? 0 : 2,
      shadowColor: const Color(0xFF102B5B).withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: PhotoToolUi.border(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${group.copyCount} identical copies · '
                    '${ByteFormatter.format(group.fileBytes)} each',
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  'save ${ByteFormatter.format(group.reclaimableBytes)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: PhotoToolUi.orange(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (original != null) _KeptRow(file: original),
            for (final ScannedFile copy in group.duplicates)
              PhotoToolFilePanel(
                child: ScannedFileTile(
                  file: copy,
                  selectionMode: true,
                  selected: selection.contains(copy),
                  onTap: () => onToggle(copy),
                  onLongPress: () => showFileDetails(context, copy),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The copy that will be kept. Deliberately not selectable.
class _KeptRow extends StatelessWidget {
  const _KeptRow({required this.file});

  final ScannedFile file;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Container(
      key: Key('duplicate_kept_${file.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          PhosphorIcon(
            PhosphorIconsDuotone.shieldCheck,
            size: 20,
            color: PhotoToolUi.primary(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  'Kept · ${DateFormatter.relative(file.dateModified)}',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Headline: how much a full clean-up would recover.
class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.result});

  final DuplicateScanResult result;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Card(
      key: const Key('duplicates_total_card'),
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
              'Recoverable by removing copies',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              ByteFormatter.format(result.reclaimableBytes),
              key: const Key('duplicates_total_bytes'),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: PhotoToolUi.orange(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${result.duplicateCount} extra '
              '${result.duplicateCount == 1 ? 'copy' : 'copies'} across '
              '${result.groupCount} '
              '${result.groupCount == 1 ? 'set' : 'sets'}',
              key: const Key('duplicates_count'),
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                PhosphorIcon(
                  PhosphorIconsDuotone.sealCheck,
                  size: 15,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Matched byte for byte. One copy of each set is always '
                    'kept.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
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

/// Hashing can take a moment, so say so rather than showing a bare spinner.
class _HashingView extends StatelessWidget {
  const _HashingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      key: Key('duplicates_scanning'),
      child: PhotoToolLoadingState(
        icon: PhosphorIconsDuotone.copy,
        title: 'Comparing files…',
        description: 'Only files of matching size are read.',
      ),
    );
  }
}

class _NoDuplicates extends StatelessWidget {
  const _NoDuplicates();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return ListView(
      key: const Key('duplicates_empty'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: <Widget>[
        const SizedBox(height: 60),
        PhosphorIcon(
          PhosphorIconsDuotone.checkCircle,
          size: 64,
          color: PhotoToolUi.primary(context),
          duotoneSecondaryColor: PhotoToolUi.orange(context),
          duotoneSecondaryOpacity: 0.9,
        ),
        const SizedBox(height: 16),
        Text(
          'No duplicates found',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'No two files on this phone are byte for byte identical.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}
