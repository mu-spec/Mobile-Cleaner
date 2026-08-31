import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';
import 'package:mobile_cleaner/core/ui/haptics.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/files/data/delete_repository.dart';
import 'package:mobile_cleaner/features/files/domain/delete_result.dart';
import 'package:mobile_cleaner/features/files/domain/file_category.dart';
import 'package:mobile_cleaner/features/files/domain/file_selection.dart';
import 'package:mobile_cleaner/features/files/domain/scanned_file.dart';
import 'package:mobile_cleaner/features/files/presentation/screens/cleanup_complete_screen.dart';
import 'package:mobile_cleaner/features/history/presentation/providers/cleanup_history_provider.dart';
import 'package:mobile_cleaner/features/home/presentation/providers/recommendations_provider.dart';
import 'package:mobile_cleaner/features/storage/presentation/providers/storage_overview_provider.dart';
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

class _CleanupFlowScreenState extends ConsumerState<_CleanupFlowScreen>
    with TickerProviderStateMixin {
  late final List<_CleanupGroup> _groups = _buildGroups(widget.files);
  late final int _plannedBytes = widget.files.fold<int>(
    0,
    (int total, ScannedFile file) => total + file.sizeBytes,
  );
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1350),
  );
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1750),
  );

  _CleanupStage _stage = _CleanupStage.review;
  DeleteResult? _result;
  Duration _cleanupDuration = Duration.zero;
  bool _starting = false;

  @override
  void dispose() {
    _progress.dispose();
    _rotation.dispose();
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
    _rotation.repeat();

    // Begin the platform operation immediately. The progress animation runs
    // beside it, stopping at 90% if Android still needs user confirmation.
    final Future<DeleteResult> cleanup = ref
        .read(deleteRepositoryProvider)
        .deleteFiles(widget.files);
    await _progress.animateTo(
      0.9,
      duration: const Duration(milliseconds: 1350),
      curve: Curves.easeOutCubic,
    );
    final DeleteResult result = await cleanup;

    if (!mounted) {
      return;
    }

    await _progress.animateTo(
      1,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOut,
    );
    _rotation.stop();
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
        plannedBytes: _plannedBytes,
        progress: _progress,
        rotation: _rotation,
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

class _CleaningScreen extends StatelessWidget {
  const _CleaningScreen({
    required this.files,
    required this.groups,
    required this.plannedBytes,
    required this.progress,
    required this.rotation,
  });

  final List<ScannedFile> files;
  final List<_CleanupGroup> groups;
  final int plannedBytes;
  final Animation<double> progress;
  final Animation<double> rotation;

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: false,
      child: Scaffold(
        key: const Key('delete_progress'),
        appBar: AppBar(
          leading: IconButton(
            key: const Key('cleanup_cleaning_back'),
            tooltip: 'Back',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please wait while cleanup finishes.'),
                ),
              );
            },
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: const Text('Cleaning...'),
        ),
        body: SafeArea(
          child: AnimatedBuilder(
            animation: progress,
            builder: (BuildContext context, Widget? child) {
              final double value = progress.value.clamp(0, 1);
              final int currentBytes = (plannedBytes * value).round();
              final int fileIndex = files.isEmpty
                  ? 0
                  : ((files.length - 1) * value).floor().clamp(
                      0,
                      files.length - 1,
                    );
              final ScannedFile? current = files.isEmpty
                  ? null
                  : files[fileIndex];

              return ListView(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 24),
                children: <Widget>[
                  Center(
                    child: _CleaningOrb(progress: value, rotation: rotation),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    ByteFormatter.format(currentBytes),
                    key: const Key('cleanup_cleaning_bytes'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.brandBlue,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Cleaning...',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    current?.path.isNotEmpty == true
                        ? current!.path
                        : (current?.name ?? 'Preparing selected items'),
                    key: const Key('cleanup_current_file'),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _GradientProgressBar(value: value),
                  const SizedBox(height: 18),
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.darkSurfaceElevated
                          : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AppColors.darkBorder
                            : AppColors.border,
                      ),
                    ),
                    child: Column(
                      children: <Widget>[
                        for (
                          int index = 0;
                          index < groups.length;
                          index++
                        ) ...<Widget>[
                          _CleaningGroupRow(
                            group: groups[index],
                            progress: value,
                            groupStart: _groupStart(groups, index),
                            groupEnd: _groupEnd(groups, index),
                          ),
                          if (index != groups.length - 1)
                            const Divider(height: 1, indent: 62),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CleaningOrb extends StatelessWidget {
  const _CleaningOrb({required this.progress, required this.rotation});

  final double progress;
  final Animation<double> rotation;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 166,
      height: 166,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Positioned.fill(
            child: AnimatedBuilder(
              animation: rotation,
              builder: (BuildContext context, Widget? child) {
                return Transform.rotate(
                  angle: rotation.value * 6.283185307179586,
                  child: CustomPaint(
                    painter: _CleaningRingPainter(progress: progress),
                  ),
                );
              },
            ),
          ),
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[AppColors.actionBlue, AppColors.brandBlue],
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: AppColors.actionBlue.withValues(alpha: 0.32),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              PhosphorIconsDuotone.broom,
              color: Colors.white,
              size: 52,
            ),
          ),
        ],
      ),
    );
  }
}

class _CleaningRingPainter extends CustomPainter {
  const _CleaningRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = (size.shortestSide - 16) / 2;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);
    final Paint track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = AppColors.softBlue;
    canvas.drawCircle(center, radius, track);

    final Paint active = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 10
      ..shader = const SweepGradient(
        colors: <Color>[
          AppColors.cleanupOrange,
          AppColors.actionBlue,
          AppColors.brandBlue,
        ],
      ).createShader(rect);
    canvas.drawArc(
      rect,
      -1.5707963267948966,
      6.283185307179586 * progress,
      false,
      active,
    );

    final Paint halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = AppColors.actionBlue.withValues(alpha: 0.2);
    canvas.drawCircle(center, radius - 16, halo);
  }

  @override
  bool shouldRepaint(_CleaningRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _GradientProgressBar extends StatelessWidget {
  const _GradientProgressBar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: Container(
        key: const Key('cleanup_progress_bar'),
        height: 8,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: value,
          child: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  AppColors.cleanupOrange,
                  AppColors.actionBlue,
                  AppColors.brandBlue,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CleaningGroupRow extends StatelessWidget {
  const _CleaningGroupRow({
    required this.group,
    required this.progress,
    required this.groupStart,
    required this.groupEnd,
  });

  final _CleanupGroup group;
  final double progress;
  final double groupStart;
  final double groupEnd;

  @override
  Widget build(BuildContext context) {
    final bool done = progress >= groupEnd || progress >= 0.999;
    final bool active = progress >= groupStart && !done;
    final double local = groupEnd <= groupStart
        ? 1
        : ((progress - groupStart) / (groupEnd - groupStart)).clamp(0, 1);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: <Widget>[
          _CategoryIcon(group: group),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              group.label,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (done)
            Text(
              'Done',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.brandBlue,
                fontWeight: FontWeight.w700,
              ),
            )
          else if (active)
            Text(
              '${ByteFormatter.format((group.totalBytes * local).round())} / '
              '${ByteFormatter.format(group.totalBytes)}',
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            )
          else
            Text(
              ByteFormatter.format(group.totalBytes),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(width: 8),
          Icon(
            done
                ? PhosphorIconsDuotone.checkSquare
                : PhosphorIconsDuotone.circleNotch,
            size: 20,
            color: done
                ? AppColors.brandBlue
                : Theme.of(context).colorScheme.onSurfaceVariant,
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

double _groupStart(List<_CleanupGroup> groups, int index) {
  final int total = groups.fold<int>(
    0,
    (int sum, _CleanupGroup group) => sum + group.totalBytes,
  );
  if (total == 0) {
    return index / groups.length;
  }
  final int before = groups
      .take(index)
      .fold<int>(0, (int sum, _CleanupGroup group) => sum + group.totalBytes);
  return before / total;
}

double _groupEnd(List<_CleanupGroup> groups, int index) {
  if (index == groups.length - 1) {
    return 1;
  }
  return _groupStart(groups, index + 1);
}
