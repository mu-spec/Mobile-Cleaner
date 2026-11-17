import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phone_storage_cleaner/app/theme/app_colors.dart';
import 'package:phone_storage_cleaner/core/ui/haptics.dart';
import 'package:phone_storage_cleaner/core/ui/circular_file_scanner.dart';
import 'package:phone_storage_cleaner/core/ui/reference_progress_art.dart';
import 'package:phone_storage_cleaner/features/files/domain/delete_progress.dart';
import 'package:phone_storage_cleaner/core/utils/byte_formatter.dart';
import 'package:phone_storage_cleaner/features/files/data/delete_repository.dart';
import 'package:phone_storage_cleaner/features/files/domain/delete_result.dart';
import 'package:phone_storage_cleaner/features/files/domain/file_category.dart';
import 'package:phone_storage_cleaner/features/files/domain/file_selection.dart';
import 'package:phone_storage_cleaner/features/files/domain/scanned_file.dart';
import 'package:phone_storage_cleaner/features/files/presentation/screens/cleanup_complete_screen.dart';
import 'package:phone_storage_cleaner/features/history/presentation/providers/cleanup_history_provider.dart';
import 'package:phone_storage_cleaner/features/home/presentation/providers/recommendations_provider.dart';
import 'package:phone_storage_cleaner/features/storage/presentation/providers/storage_overview_provider.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Opens the shared three-screen cleanup experience used by every cleaner.
///
/// The route owns Review Cleanup, live Cleaning progress, and Cleanup Complete.
/// It returns the platform's exact result so the calling tool can remove only
/// files that Android confirmed were cleaned.
Future<DeleteResult?> runDeleteFlow({
  required BuildContext context,
  required WidgetRef ref,
  required FileSelection selection,
}) async {
  if (selection.isEmpty) {
    return null;
  }

  final List<ScannedFile> files = selection.deletableFiles.toList(
    growable: false,
  );
  if (files.isEmpty) {
    return null;
  }

  return Navigator.of(context).push<DeleteResult>(
    MaterialPageRoute<DeleteResult>(
      builder: (BuildContext routeContext) => _CleanupFlowScreen(files: files),
    ),
  );
}

enum _CleanupStage { review, cleaning, complete }

class _CleanupFlowScreen extends ConsumerStatefulWidget {
  const _CleanupFlowScreen({required this.files});

  final List<ScannedFile> files;

  @override
  ConsumerState<_CleanupFlowScreen> createState() => _CleanupFlowScreenState();
}

class _CleanupFlowScreenState extends ConsumerState<_CleanupFlowScreen> {
  late final List<_CleanupGroup> _groups = _buildGroups(widget.files);
  late final int _plannedBytes = widget.files.fold<int>(
    0,
    (int total, ScannedFile file) => total + file.sizeBytes,
  );
  late final DeleteProgressOperation _deletion = DeleteProgressOperation(
    widget.files,
  );

  @override
  void initState() {
    super.initState();
    _deletion.addListener(_onProgress);
  }

  void _onProgress() {
    if (mounted) setState(() {});
  }

  _CleanupStage _stage = _CleanupStage.review;
  DeleteResult? _result;
  Duration _cleanupDuration = Duration.zero;
  bool _starting = false;

  @override
  void dispose() {
    _deletion.removeListener(_onProgress);
    _deletion.dispose();
    super.dispose();
  }

  Future<void> _startCleanup() async {
    if (_starting) {
      return;
    }
    _starting = true;
    Haptics.warning();
    setState(() => _stage = _CleanupStage.cleaning);

    final Stopwatch stopwatch = Stopwatch()..start();
    DeleteResult result;
    try {
      result = await _deletion.run(
        () => ref.read(deleteRepositoryProvider).deleteFiles(widget.files),
      );
    } catch (_) {
      // Unknown outcomes are failures, never animation-driven successes.
      result = DeleteResult(
        deletedFiles: const [],
        failures: [
          for (final file in widget.files)
            DeleteFailure(
              uri: file.uri,
              reason: 'Deletion could not be confirmed.',
            ),
        ],
      );
    }
    stopwatch.stop();

    if (!mounted) {
      return;
    }

    if (result.deletedCount > 0) {
      Haptics.success();
      ref.invalidate(storageOverviewProvider);
      ref.read(recommendationsProvider.notifier).invalidateAfterCleanup();
      unawaited(
        recordCleanup(
          ref,
          filesRemoved: result.deletedCount,
          bytesRecovered: result.freedBytes,
        ),
      );
      setState(() {
        _result = result;
        _cleanupDuration = stopwatch.elapsed;
        _stage = _CleanupStage.complete;
      });
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) =>
          _CleanupResultDialog(result: result),
    );
    if (mounted) {
      Navigator.of(context).pop(result);
    }
  }

  void _finish() {
    Navigator.of(context).pop(_result);
  }

  @override
  Widget build(BuildContext context) {
    return switch (_stage) {
      _CleanupStage.review => _ReviewCleanupScreen(
        files: widget.files,
        groups: _groups,
        plannedBytes: _plannedBytes,
        onClean: _startCleanup,
      ),
      _CleanupStage.cleaning => _CleaningScreen(
        files: widget.files,
        groups: _groups,
        snapshot: _deletion.snapshot,
        operationId: _deletion.id,
      ),
      _CleanupStage.complete => CleanupCompleteScreen(
        result: _result!,
        cleanupDuration: _cleanupDuration,
        onDone: _finish,
      ),
    };
  }
}

class _ReviewCleanupScreen extends StatelessWidget {
  const _ReviewCleanupScreen({
    required this.files,
    required this.groups,
    required this.plannedBytes,
    required this.onClean,
  });

  final List<ScannedFile> files;
  final List<_CleanupGroup> groups;
  final int plannedBytes;
  final VoidCallback onClean;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool dark = theme.brightness == Brightness.dark;

    return Scaffold(
      key: const Key('cleanup_review_screen'),
      appBar: AppBar(
        leading: IconButton(
          key: const Key('delete_cancel'),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Review Cleanup'),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                children: <Widget>[
                  _CleanupHero(files: files, plannedBytes: plannedBytes),
                  const SizedBox(height: 24),
                  Text(
                    'Breakdown',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: dark
                          ? AppColors.darkSurfaceElevated
                          : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: dark ? AppColors.darkBorder : AppColors.border,
                      ),
                    ),
                    child: Column(
                      children: <Widget>[
                        for (
                          int index = 0;
                          index < groups.length;
                          index++
                        ) ...<Widget>[
                          _ReviewBreakdownRow(group: groups[index]),
                          if (index != groups.length - 1)
                            Divider(
                              height: 1,
                              indent: 62,
                              color: colors.outlineVariant.withValues(
                                alpha: 0.55,
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        PhosphorIconsDuotone.shieldCheck,
                        size: 18,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Only the selected items will be cleaned. Cleaned '
                          'items cannot be restored.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: _OrangeActionButton(
                key: const Key('delete_confirm'),
                label: 'Clean Now (${ByteFormatter.format(plannedBytes)})',
                onPressed: onClean,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CleanupHero extends StatelessWidget {
  const _CleanupHero({required this.files, required this.plannedBytes});

  final List<ScannedFile> files;
  final int plannedBytes;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('delete_review_title'),
      height: 210,
      padding: const EdgeInsets.fromLTRB(20, 20, 8, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[AppColors.brandBlue, AppColors.actionBlue],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.actionBlue.withValues(alpha: 0.24),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  ByteFormatter.format(plannedBytes),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Ready to clean',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Selected items can be safely removed from your device.',
                  key: const Key('delete_review_summary'),
                  maxLines: 2,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.84),
                    height: 1.35,
                  ),
                ),
                const Spacer(),
                Text(
                  '${files.length} '
                  '${files.length == 1 ? 'item' : 'items'} selected',
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: Colors.white.withValues(alpha: 0.72)),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 4,
            child: Stack(
              key: const Key('cleanup_review_illustration_frame'),
              alignment: Alignment.center,
              clipBehavior: Clip.hardEdge,
              children: <Widget>[
                Container(
                  width: 118,
                  height: 118,
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: <Color>[
                        Colors.white.withValues(alpha: 0.13),
                        AppColors.cleanupOrange.withValues(alpha: 0.12),
                      ],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppColors.cleanupOrange.withValues(alpha: 0.16),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
                Transform.scale(
                  scale: 1.75,
                  child: Image.asset(
                    'assets/images/cleanup_summary_bin.png',
                    key: const Key('cleanup_review_illustration'),
                    width: 126,
                    height: 126,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    semanticLabel: 'Cleanup basket',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewBreakdownRow extends StatelessWidget {
  const _ReviewBreakdownRow({required this.group});

  final _CleanupGroup group;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      key: Key('cleanup_breakdown_${group.category.key}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: <Widget>[
          _CategoryIcon(group: group),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  group.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${group.files.length} '
                  '${group.files.length == 1 ? 'item' : 'items'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            ByteFormatter.format(group.totalBytes),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 10),
          const Icon(
            PhosphorIconsDuotone.checkSquare,
            size: 21,
            color: AppColors.brandBlue,
          ),
        ],
      ),
    );
  }
}

/// Live cleaning is evidence-driven. No planned-byte multiplication, fake
/// current-file index, weighted category completion or timer-based progress.
class _CleaningScreen extends StatelessWidget {
  const _CleaningScreen({
    required this.files,
    required this.groups,
    required this.snapshot,
    required this.operationId,
  });
  final String operationId;
  final List<ScannedFile> files;
  final List<_CleanupGroup> groups;
  final DeleteProgressSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final current = files
        .where((file) => file.uri == snapshot.currentUri)
        .firstOrNull;
    final status = switch (snapshot.phase) {
      'awaitingConfirmation' => 'Waiting for Android confirmation…',
      'awaitingPermission' => 'Waiting for permission…',
      'verifying' => 'Verifying removal…',
      'preparing' => 'Preparing selected items…',
      _ => 'Cleaning…',
    };
    return PopScope<void>(
      canPop: false,
      child: Scaffold(
        key: const Key('delete_progress'),
        appBar: AppBar(
          leading: IconButton(
            key: const Key('cleanup_cleaning_back'),
            tooltip: 'Back',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Please wait while cleanup finishes.'),
              ),
            ),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: const Text('Cleaning...'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
            children: [
              Center(
                child: CleaningProgressAnimation(
                  progress: snapshot.fraction,
                  active: !snapshot.terminal,
                  operationId: operationId,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                ByteFormatter.format(snapshot.confirmedBytes),
                key: const Key('cleanup_cleaning_bytes'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: ReferenceProgressColors.deep,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                status,
                key: const Key('cleanup_cleaning_status'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                current == null
                    ? 'Only confirmed removals count'
                    : current.path.isNotEmpty
                    ? current.path
                    : current.name,
                key: const Key('cleanup_current_file'),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              ReferenceProgressBar(
                key: const Key('cleanup_progress_bar'),
                value: snapshot.fraction,
              ),
              const SizedBox(height: 8),
              Text(
                '${snapshot.processed} / ${snapshot.total} items processed · '
                '${snapshot.deleted.length} cleaned',
                key: const Key('cleanup_processed_count'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 22),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.darkSurfaceElevated
                      : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Column(
                  children: [
                    for (final group in groups)
                      _CleaningGroupRow(group: group, snapshot: snapshot),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Separate broom treatment with lifecycle-aware pulse/shine. No rotation of
/// the orange arc: its sweep is exclusively confirmed processed / selected.
class CleaningProgressAnimation extends StatelessWidget {
  const CleaningProgressAnimation({
    required this.progress,
    this.active = true,
    this.operationId,
    super.key,
  });
  final double? progress;
  final bool active;
  final Object? operationId;
  @override
  Widget build(BuildContext context) => CircularFileScanner(
    size: 190,
    cleaning: true,
    scanId: operationId,
    progress: progress,
    active: active,
  );
}

class _CleaningGroupRow extends StatelessWidget {
  const _CleaningGroupRow({required this.group, required this.snapshot});
  final _CleanupGroup group;
  final DeleteProgressSnapshot snapshot;
  @override
  Widget build(BuildContext context) {
    final uris = group.files.map((file) => file.uri).toSet();
    final deleted = uris.intersection(snapshot.deleted).length;
    final failed = uris.intersection(snapshot.failed).length;
    final skipped = uris.intersection(snapshot.skipped).length;
    final allDeleted = deleted == uris.length && uris.isNotEmpty;
    final label = allDeleted
        ? 'Done'
        : failed > 0 || skipped > 0
        ? '$deleted cleaned · $failed failed · $skipped skipped'
        : '$deleted / ${uris.length} cleaned';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          _CategoryIcon(group: group),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              group.label,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            allDeleted
                ? PhosphorIconsDuotone.checkSquare
                : PhosphorIconsDuotone.circleNotch,
            size: 20,
            color: ReferenceProgressColors.blue,
          ),
        ],
      ),
    );
  }
}

class _CategoryIcon extends StatelessWidget {
  const _CategoryIcon({required this.group});

  final _CleanupGroup group;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppColors.softBlue,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(group.icon, size: 20, color: AppColors.actionBlue),
    );
  }
}

class _OrangeActionButton extends StatelessWidget {
  const _OrangeActionButton({
    required this.label,
    required this.onPressed,
    super.key,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: <Color>[AppColors.cleanupOrange, Color(0xFFFFA217)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppColors.cleanupOrange.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onPressed,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    PhosphorIconsDuotone.broom,
                    size: 20,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CleanupResultDialog extends StatelessWidget {
  const _CleanupResultDialog({required this.result});

  final DeleteResult result;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final bool cancelled = result.userCancelled;

    return AlertDialog(
      key: const Key('delete_result_dialog'),
      icon: Icon(
        cancelled ? PhosphorIconsDuotone.info : PhosphorIconsDuotone.warning,
        color: cancelled ? colors.onSurfaceVariant : colors.error,
        size: 34,
      ),
      title: Text(
        cancelled ? 'Nothing cleaned' : 'Could not clean',
        key: const Key('delete_result_title'),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            cancelled
                ? 'The cleanup was cancelled.'
                : result.skippedUris.isNotEmpty
                ? 'These items were already absent or skipped. No new space was counted.'
                : 'The selected items could not be removed.',
          ),
          if (result.failureCount > 0) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              '${result.failureCount} '
              '${result.failureCount == 1 ? 'item' : 'items'} could not be cleaned.',
              key: const Key('delete_result_failed'),
              style: TextStyle(color: colors.error),
            ),
            const SizedBox(height: 4),
            Text(
              result.failures.first.reason,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        FilledButton(
          key: const Key('delete_result_done'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _CleanupGroup {
  const _CleanupGroup({
    required this.category,
    required this.label,
    required this.icon,
    required this.files,
    required this.totalBytes,
  });

  final FileCategory category;
  final String label;
  final IconData icon;
  final List<ScannedFile> files;
  final int totalBytes;
}

List<_CleanupGroup> _buildGroups(List<ScannedFile> files) {
  final Map<FileCategory, List<ScannedFile>> grouped =
      <FileCategory, List<ScannedFile>>{};
  for (final ScannedFile file in files) {
    grouped.putIfAbsent(file.category, () => <ScannedFile>[]).add(file);
  }

  final List<_CleanupGroup> groups = grouped.entries
      .map((entry) {
        final FileCategory category = entry.key;
        return _CleanupGroup(
          category: category,
          label: _cleanupLabel(category),
          icon: _cleanupIcon(category),
          files: List<ScannedFile>.unmodifiable(entry.value),
          totalBytes: entry.value.fold<int>(
            0,
            (int total, ScannedFile file) => total + file.sizeBytes,
          ),
        );
      })
      .toList(growable: false);
  groups.sort(
    (_CleanupGroup a, _CleanupGroup b) => b.totalBytes.compareTo(a.totalBytes),
  );
  return groups;
}

String _cleanupLabel(FileCategory category) => switch (category) {
  FileCategory.images => 'Photos',
  FileCategory.videos => 'Videos',
  FileCategory.audio => 'Audio',
  FileCategory.documents => 'Documents',
  FileCategory.downloads => 'Old Downloads',
  FileCategory.apks => 'APK Installers',
  FileCategory.other => 'Large Files',
};

IconData _cleanupIcon(FileCategory category) => switch (category) {
  FileCategory.images => PhosphorIconsDuotone.imagesSquare,
  FileCategory.videos => PhosphorIconsDuotone.videoCamera,
  FileCategory.audio => PhosphorIconsDuotone.musicNotes,
  FileCategory.documents => PhosphorIconsDuotone.fileText,
  FileCategory.downloads => PhosphorIconsDuotone.downloadSimple,
  FileCategory.apks => PhosphorIconsDuotone.androidLogo,
  FileCategory.other => PhosphorIconsDuotone.folder,
};
