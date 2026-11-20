import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phone_storage_cleaner/app/router/app_router.dart';
import 'package:phone_storage_cleaner/app/theme/app_colors.dart';
import 'package:phone_storage_cleaner/app/theme/app_tokens.dart';
import 'package:phone_storage_cleaner/core/scanning/scan_progress.dart';
import 'package:phone_storage_cleaner/core/ui/scan_stage_presentation.dart';
import 'package:phone_storage_cleaner/core/ui/smart_scan_progress.dart';
import 'package:phone_storage_cleaner/features/apps/presentation/providers/installed_apps_provider.dart';
import 'package:phone_storage_cleaner/features/cleaner/domain/scan_launch_target.dart';
import 'package:phone_storage_cleaner/features/files/domain/screenshot_filter.dart';
import 'package:phone_storage_cleaner/features/files/domain/video_sort.dart';
import 'package:phone_storage_cleaner/features/files/presentation/providers/duplicates_provider.dart';
import 'package:phone_storage_cleaner/features/files/presentation/providers/file_scan_provider.dart';
import 'package:phone_storage_cleaner/features/files/presentation/providers/photo_cleanup_provider.dart';
import 'package:phone_storage_cleaner/features/files/presentation/providers/screenshot_provider.dart';
import 'package:phone_storage_cleaner/features/files/presentation/providers/videos_provider.dart';
import 'package:phone_storage_cleaner/features/home/presentation/providers/recommendations_provider.dart';

/// Runs the existing real scan and preserves its presentation timing gates.
///
/// Request-scoped measured work drives the ring when a reliable denominator
/// exists. Unknown-total discovery remains indeterminate. Timing gates pace only
/// the existing transition and never contribute to scanning progress.
class ScanProgressScreen extends ConsumerStatefulWidget {
  const ScanProgressScreen({required this.target, super.key});

  final ScanLaunchTarget target;

  @override
  ConsumerState<ScanProgressScreen> createState() => _ScanProgressScreenState();
}

class _ScanProgressScreenState extends ConsumerState<ScanProgressScreen> {
  Object? _scanError;
  bool _completed = false;
  bool _running = false;
  bool _finished = false;
  bool _navigated = false;
  ScanOperation? _operation;
  ScanSnapshot? _snapshot;
  StreamSubscription<ScanSnapshot>? _progressSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
  }

  @override
  void dispose() {
    unawaited(_progressSubscription?.cancel());
    _progressSubscription = null;
    _operation?.cancel();
    super.dispose();
  }

  Future<void> _startScan() async {
    if (_running) {
      return;
    }
    _running = true;
    _operation?.cancel();
    unawaited(_progressSubscription?.cancel());
    if (!mounted) return;
    final operation = ScanOperation(
      numeric:
          widget.target == ScanLaunchTarget.screenshots ||
          widget.target == ScanLaunchTarget.largeVideos ||
          widget.target == ScanLaunchTarget.apps,
    );
    _operation = operation;
    _snapshot = operation.snapshot;
    _progressSubscription = operation.updates.listen((snapshot) {
      if (mounted && identical(_operation, operation)) {
        setState(() => _snapshot = snapshot);
      }
    });
    setState(() {
      _scanError = null;
      _completed = false;
      _finished = false;
      _navigated = false;
    });

    try {
      await operation.run(_runRealScan);
      if (!mounted || !identical(_operation, operation)) {
        return;
      }
      if (!operation.snapshot.successful) {
        return;
      }
      setState(() {
        _completed = true;
        _finished = true;
      });
      if (!_navigated) {
        _navigated = true;
        _openResults();
      }
    } catch (error) {
      if (mounted && identical(_operation, operation)) {
        setState(() => _scanError = error);
      }
    } finally {
      if (identical(_operation, operation)) {
        _running = false;
      }
    }
  }

  Future<T> _required<T>(String module, Future<T> future) {
    ref.read(scanProgressRegistryProvider).attachCurrent(module);
    return future;
  }

  Future<void> _runRealScan() async {
    switch (widget.target) {
      case ScanLaunchTarget.smartScan:
        await ref.read(recommendationsProvider.notifier).scan();
        return;
      case ScanLaunchTarget.screenshots:
        ref.invalidate(screenshotScanProvider);
        ref.invalidate(screenshotSummaryProvider);
        await _required(
          'screenshots',
          ref.read(
            screenshotSummaryProvider(ScreenshotGroup.defaultGroup).future,
          ),
        );
        return;
      case ScanLaunchTarget.duplicates:
        ref.invalidate(duplicateScanProvider);
        ref.invalidate(duplicatesProvider);
        await _required('duplicates', ref.read(duplicatesProvider.future));
        return;
      case ScanLaunchTarget.largeVideos:
        ref.invalidate(videoScanProvider);
        ref.invalidate(videoSummaryProvider);
        await _required(
          'videos',
          ref.read(videoSummaryProvider(VideoSort.largest).future),
        );
        return;
      case ScanLaunchTarget.photoCleanup:
        refreshPhotoCleanup(ref);
        ref.invalidate(photoCleanupProvider);
        await _required('photos', ref.read(photoCleanupProvider.future));
        return;
      case ScanLaunchTarget.files:
        ref.invalidate(fileScanProvider);
        await _required('files', ref.read(fileScanProvider.future));
        return;
      case ScanLaunchTarget.apps:
        ref.invalidate(installedAppsProvider);
        await _required(
          'discovery:apps',
          ref.read(installedAppsProvider.future),
        );
        return;
    }
  }

  void _openResults() {
    final String destination = switch (widget.target) {
      ScanLaunchTarget.smartScan => AppRoutes.clean,
      ScanLaunchTarget.screenshots => AppRoutes.screenshotCleaner,
      ScanLaunchTarget.duplicates => AppRoutes.duplicates,
      ScanLaunchTarget.largeVideos => AppRoutes.videos,
      ScanLaunchTarget.photoCleanup => AppRoutes.photos,
      ScanLaunchTarget.files => AppRoutes.files,
      ScanLaunchTarget.apps => AppRoutes.apps,
    };
    if (widget.target == ScanLaunchTarget.smartScan ||
        widget.target == ScanLaunchTarget.photoCleanup ||
        widget.target == ScanLaunchTarget.files ||
        widget.target == ScanLaunchTarget.apps) {
      context.go(destination);
    } else {
      context.replace(destination);
    }
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  String get _activity => switch (widget.target) {
    ScanLaunchTarget.smartScan => 'Scanning your device...',
    ScanLaunchTarget.screenshots => 'Finding screenshots...',
    ScanLaunchTarget.duplicates => 'Checking duplicate files...',
    ScanLaunchTarget.largeVideos => 'Checking large videos...',
    ScanLaunchTarget.photoCleanup => 'Scanning your photos...',
    ScanLaunchTarget.files => 'Checking files...',
    ScanLaunchTarget.apps => 'Analyzing your apps...',
  };

  String _support(ScanSnapshot? shown) {
    final stage = (shown?.displayStage?.name ?? shown?.stage ?? '')
        .toLowerCase();
    if (stage.contains('fingerprint')) return 'Comparing photo fingerprints';
    if (stage.contains('hash')) return 'Checking file fingerprints';
    if (stage.contains('quality')) return 'Reviewing photo quality';
    if (stage.contains('app')) return 'Reviewing installed apps';
    if (stage.contains('group') || stage.contains('compar')) {
      return 'Comparing scanned items';
    }
    return 'Checking files on your device';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ScanStagePresentation(
      snapshot: _snapshot,
      builder: (context, shown) => Scaffold(
        key: const Key('scan_progress_screen'),
        backgroundColor: isDark
            ? AppColors.darkBackground
            : const Color(0xFFF8FAFE),
        appBar: AppBar(
          leadingWidth: 66,
          leading: IconButton(
            key: const Key('scan_progress_back_button'),
            tooltip: 'Back',
            onPressed: _goBack,
            icon: Transform.translate(
              offset: const Offset(0, 12),
              child: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          foregroundColor: isDark ? Colors.white : const Color(0xFF080E24),
          titleSpacing: 17,
          title: Transform.translate(
            offset: const Offset(0, 12),
            child: const Text(
              'Smart Scan',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -.6,
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: SmartScanProgress(
            snapshot: shown,
            activity: shown?.displayStage == null
                ? _activity
                : '${shown!.displayStage!.name}...',
            description: _support(shown),
            active: !_finished && _scanError == null,
            completed: _completed,
            succeeded: _snapshot?.successful ?? false,
            footer: _scanError == null
                ? null
                : _ScanErrorCard(
                    onRetry: _startScan,
                    onCancel: () => context.go(AppRoutes.home),
                  ),
          ),
        ),
      ),
    );
  }
}

class _ScanErrorCard extends StatelessWidget {
  const _ScanErrorCard({required this.onRetry, required this.onCancel});

  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('scan_progress_error'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        children: <Widget>[
          const Icon(Icons.error_outline_rounded, size: 36),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'We could not finish this scan.',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              TextButton(onPressed: onCancel, child: const Text('Back home')),
              const SizedBox(width: AppSpacing.xs),
              FilledButton(
                key: const Key('scan_progress_retry'),
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
