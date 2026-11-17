import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phone_storage_cleaner/app/router/app_router.dart';
import 'package:phone_storage_cleaner/app/theme/app_colors.dart';
import 'package:phone_storage_cleaner/app/theme/app_tokens.dart';
import 'package:phone_storage_cleaner/core/ui/circular_file_scanner.dart';
import 'package:phone_storage_cleaner/features/apps/presentation/providers/installed_apps_provider.dart';
import 'package:phone_storage_cleaner/features/cleaner/domain/scan_launch_target.dart';
import 'package:phone_storage_cleaner/features/files/presentation/providers/duplicates_provider.dart';
import 'package:phone_storage_cleaner/features/files/presentation/providers/file_scan_provider.dart';
import 'package:phone_storage_cleaner/features/files/presentation/providers/photo_cleanup_provider.dart';
import 'package:phone_storage_cleaner/features/files/presentation/providers/screenshot_provider.dart';
import 'package:phone_storage_cleaner/features/files/presentation/providers/videos_provider.dart';
import 'package:phone_storage_cleaner/features/home/presentation/providers/recommendations_provider.dart';
import 'package:phone_storage_cleaner/features/home/presentation/widgets/home_upper_style.dart';

/// Runs the existing real scan and preserves its presentation timing gates.
///
/// Native scanning has no incremental progress API, so the scanner visual is
/// indeterminate. Timing controllers below pace the existing screen transition
/// only; they are never presented as measured progress.
class ScanProgressScreen extends ConsumerStatefulWidget {
  const ScanProgressScreen({required this.target, super.key});

  final ScanLaunchTarget target;

  @override
  ConsumerState<ScanProgressScreen> createState() => _ScanProgressScreenState();
}

class _ScanProgressScreenState extends ConsumerState<ScanProgressScreen>
    with TickerProviderStateMixin {
  late final AnimationController _progressController;
  late final AnimationController _completionController;
  Object? _scanError;
  bool _completed = false;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    _completionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
  }

  @override
  void dispose() {
    _progressController.dispose();
    _completionController.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    if (_running) {
      return;
    }
    _running = true;
    setState(() {
      _scanError = null;
      _completed = false;
    });
    _progressController.reset();
    _completionController.reset();

    try {
      await Future.wait<void>(<Future<void>>[
        _progressController.forward(),
        _runRealScan(),
      ]);
      if (!mounted) {
        return;
      }
      await _completionController.forward();
      if (!mounted) {
        return;
      }
      setState(() => _completed = true);
      await Future<void>.delayed(const Duration(milliseconds: 420));
      if (mounted) {
        _openResults();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _scanError = error);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _runRealScan() async {
    switch (widget.target) {
      case ScanLaunchTarget.smartScan:
        await ref.read(recommendationsProvider.notifier).scan();
        return;
      case ScanLaunchTarget.screenshots:
        ref.invalidate(screenshotScanProvider);
        await ref.read(screenshotScanProvider.future);
        return;
      case ScanLaunchTarget.duplicates:
        ref.invalidate(duplicateScanProvider);
        ref.invalidate(duplicatesProvider);
        await ref.read(duplicatesProvider.future);
        return;
      case ScanLaunchTarget.largeVideos:
        ref.invalidate(videoScanProvider);
        await ref.read(videoScanProvider.future);
        return;
      case ScanLaunchTarget.photoCleanup:
        refreshPhotoCleanup(ref);
        ref.invalidate(photoCleanupProvider);
        await ref.read(photoCleanupProvider.future);
        return;
      case ScanLaunchTarget.files:
        ref.invalidate(fileScanProvider);
        await ref.read(fileScanProvider.future);
        return;
      case ScanLaunchTarget.apps:
        ref.invalidate(installedAppsProvider);
        await ref.read(installedAppsProvider.future);
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

  String get _scanTitle => switch (widget.target) {
    ScanLaunchTarget.smartScan => 'Scanning your storage',
    ScanLaunchTarget.screenshots => 'Finding screenshots',
    ScanLaunchTarget.duplicates => 'Finding duplicates',
    ScanLaunchTarget.largeVideos => 'Finding large videos',
    ScanLaunchTarget.photoCleanup => 'Scanning your photos',
    ScanLaunchTarget.files => 'Scanning your files',
    ScanLaunchTarget.apps => 'Analyzing your apps',
  };

  String get _scanSubtitle => switch (widget.target) {
    ScanLaunchTarget.apps => 'Reviewing installed apps safely on this device.',
    ScanLaunchTarget.photoCleanup =>
      'Reviewing your photo library safely on this device.',
    _ => 'Reviewing files safely on this device.',
  };

  String get _scanStatus {
    if (_completed) {
      return 'Scan complete';
    }
    return switch (widget.target) {
      ScanLaunchTarget.apps => 'Reading installed apps',
      ScanLaunchTarget.photoCleanup => 'Reading photo library',
      _ => 'Analyzing files',
    };
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      key: const Key('scan_progress_screen'),
      backgroundColor: isDark
          ? AppColors.darkBackground
          : HomeUpperStyle.background,
      appBar: AppBar(
        leading: IconButton(
          key: const Key('scan_progress_back_button'),
          tooltip: 'Back',
          onPressed: _goBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        backgroundColor: Colors.transparent,
        title: const Text('Smart Scan'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            children: <Widget>[
              _PrivacyBadge(isDark: isDark),
              const SizedBox(height: AppSpacing.xl),
              Text(
                _scanTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: isDark
                      ? theme.colorScheme.onSurface
                      : HomeUpperStyle.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _scanSubtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: isDark
                      ? theme.colorScheme.onSurfaceVariant
                      : HomeUpperStyle.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              CircularFileScanner(
                key: const Key('scan_progress_ring'),
                active: !_completed && _scanError == null,
                completed: _completed,
              ),
              const SizedBox(height: AppSpacing.xxl),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _scanError == null
                    ? _ScanStatusCard(
                        key: ValueKey<String>(_scanStatus),
                        completed: _completed,
                        status: _scanStatus,
                        isDark: isDark,
                      )
                    : _ScanErrorCard(
                        onRetry: _startScan,
                        onCancel: () => context.go(AppRoutes.home),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivacyBadge extends StatelessWidget {
  const _PrivacyBadge({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkInfoSurface : HomeUpperStyle.softBlue,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : const Color(0xFFD7E3FF),
        ),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.shield_rounded,
              size: 16,
              color: HomeUpperStyle.primaryBlue,
            ),
            SizedBox(width: 7),
            Text(
              'Private, on-device scan',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanStatusCard extends StatelessWidget {
  const _ScanStatusCard({
    required this.completed,
    required this.status,
    required this.isDark,
    super.key,
  });

  final bool completed;
  final String status;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: isDark ? null : HomeUpperStyle.card,
        gradient: isDark
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Color(0xFF152235),
                  AppColors.darkSurfaceElevated,
                ],
              )
            : null,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : HomeUpperStyle.border,
        ),
        boxShadow: isDark
            ? null
            : const <BoxShadow>[
                BoxShadow(
                  color: Color(0x0D12356B),
                  blurRadius: 26,
                  offset: Offset(0, 10),
                ),
              ],
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.auto_awesome_rounded,
                color: HomeUpperStyle.primaryBlue,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  status,
                  key: const Key('scan_progress_status'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: completed ? 1 : null,
              minHeight: 7,
              color: isDark
                  ? AppColors.darkPrimary
                  : HomeUpperStyle.primaryBlue,
              backgroundColor: isDark
                  ? AppColors.darkBorder
                  : const Color(0xFFE7ECF5),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Nothing is removed without your approval',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
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
