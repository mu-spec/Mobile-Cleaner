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
import 'package:mobile_cleaner/features/files/presentation/widgets/photo_tool_ui.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/scanned_file_tile.dart';
import 'package:mobile_cleaner/features/files/presentation/widgets/selection_action_bar.dart';
import 'package:mobile_cleaner/features/settings/presentation/providers/settings_provider.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

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
  /// Null until the saved default is applied, so a settings rebuild can never
  /// overwrite the group the user picked during this visit.
  ScreenshotGroup? _group;
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
    final ScreenshotGroup group =
        _group ??
        ref.watch(settingsProvider).value?.screenshotGroup ??
        ScreenshotGroup.defaultGroup;
    final AsyncValue<ScreenshotSummary> summary = ref.watch(
      screenshotSummaryProvider(group),
    );
    final bool selecting = _selection.isNotEmpty;

    return Scaffold(
      backgroundColor: PhotoToolUi.background(context),
      appBar: AppBar(
        backgroundColor: PhotoToolUi.background(context),
        surfaceTintColor: Colors.transparent,
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
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.4),
        ),
        actions: <Widget>[
          if (!selecting)
            PhotoToolActionButton(
              key: const Key('screenshot_rescan'),
              icon: Icons.refresh_rounded,
              tooltip: 'Rescan',
              onPressed: () => ref.invalidate(screenshotScanProvider),
            ),
        ],
      ),
      bottomNavigationBar: selecting
          ? SelectionActionBar(
              selection: _selection,
              onClear: _clearSelection,
              onDelete: _deleteSelected,
              deletableCount: _selection.deletableCount,
              barKey: const Key('screenshot_selection_bar'),
              countKey: const Key('screenshot_selection_count'),
              bytesKey: const Key('screenshot_selection_bytes'),
              clearKey: const Key('screenshot_selection_clear'),
              deleteKey: const Key('screenshot_selection_delete'),
            )
          : null,
      body: SafeArea(
        child: summary.when(
          loading: () => const PhotoToolLoadingState(
            icon: PhosphorIconsDuotone.deviceMobileCamera,
            title: 'Finding screenshots…',
            description: 'Reviewing your photo library safely on this device.',
          ),
          error: (Object error, StackTrace stackTrace) => FilesErrorView(
            error: error,
            onRetry: () => ref.invalidate(screenshotScanProvider),
            onPermissions: () => context.push(AppRoutes.permissions),
          ),
          data: (ScreenshotSummary data) => Column(
            children: <Widget>[
              _GroupBar(
                selected: group,
                onSelected: (ScreenshotGroup value) => _selectGroup(value),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(screenshotScanProvider);
                    await ref.read(screenshotScanProvider.future);
                  },
                  child: data.isEmpty
                      ? _EmptyScreenshots(group: group)
                      : _ScreenshotList(
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

/// Group chips: All screenshots, 30+ days, 90+ days.
class _GroupBar extends StatelessWidget {
  const _GroupBar({required this.selected, required this.onSelected});

  final ScreenshotGroup selected;
  final ValueChanged<ScreenshotGroup> onSelected;

  @override
  Widget build(BuildContext context) {
    final double textScale = MediaQuery.textScalerOf(context).scale(1);

    return Padding(
      key: const Key('screenshot_group_bar'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final int columns = constraints.maxWidth >= 360 && textScale <= 1.3
              ? 3
              : 2;
          const double gap = 8;
          final double chipWidth =
              (constraints.maxWidth - gap * (columns - 1)) / columns;

          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: <Widget>[
              for (final ScreenshotGroup option in ScreenshotGroup.values)
                SizedBox(
                  width: chipWidth,
                  child: PhotoToolChoiceChip(
                    key: Key('screenshot_group_${option.name}'),
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
          return PhotoToolSectionHeader(
            title: 'Your screenshots',
            subtitle: 'Newest first',
            icon: PhosphorIconsDuotone.deviceMobileCamera,
            trailing: TextButton.icon(
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

/// Headline: the count and total size the phase requires.
class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.summary});

  final ScreenshotSummary summary;

  @override
  Widget build(BuildContext context) {
    return PhotoToolSummaryCard(
      key: const Key('screenshot_total_card'),
      icon: PhosphorIconsDuotone.deviceMobileCamera,
      eyebrow: 'Screenshot storage',
      value: ByteFormatter.format(summary.totalBytes),
      valueKey: const Key('screenshot_total_bytes'),
      description: 'Space occupied by screenshots in this range',
      note: Row(
        children: <Widget>[
          const PhosphorIcon(
            PhosphorIconsDuotone.imagesSquare,
            size: 16,
            color: Colors.white,
          ),
          const SizedBox(width: 8),
          Text(
            '${summary.fileCount}',
            key: const Key('screenshot_count'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              summary.fileCount == 1
                  ? 'screenshot ready to review'
                  : 'screenshots ready to review',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.86)),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyScreenshots extends StatelessWidget {
  const _EmptyScreenshots({required this.group});

  final ScreenshotGroup group;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('screenshot_empty'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: <Widget>[
        PhotoToolEmptyState(
          icon: PhosphorIconsDuotone.deviceMobileCamera,
          title: group == ScreenshotGroup.all
              ? 'No screenshots found'
              : 'No screenshots ${group.description.toLowerCase()}',
          description:
              'Nothing here is taking up space. Try a different date range.',
        ),
      ],
    );
  }
}
