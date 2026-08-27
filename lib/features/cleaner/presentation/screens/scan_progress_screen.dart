import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_cleaner/app/router/app_router.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';
import 'package:mobile_cleaner/app/theme/app_tokens.dart';
import 'package:mobile_cleaner/features/cleaner/domain/scan_launch_target.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/duplicates_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/screenshot_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/smart_scan_provider.dart';
import 'package:mobile_cleaner/features/files/presentation/providers/videos_provider.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/home_upper_style.dart';

/// Runs a real storage scan behind a deliberately paced premium progress UI.
///
/// The native scanner does not expose a per-file count. The visual therefore
/// advances to 90%, waits for the requested provider to complete, and only
/// then finishes at 100% before opening the matching results screen.
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
  late final AnimationController _rotationController;
  Object? _scanError;
  bool _completed = false;
  bool _running = false;

  double get _progress {
    if (_completionController.value > 0) {
      return 0.9 +
          Curves.easeOutCubic.transform(_completionController.value) * 0.1;
    }
    return Curves.easeInOutCubic.transform(_progressController.value) * 0.9;
  }

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
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1450),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
  }

  @override
  void dispose() {
    _progressController.dispose();
    _completionController.dispose();
    _rotationController.dispose();
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
    _rotationController
      ..reset()
      ..repeat();

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
      _rotationController.stop();
      setState(() => _completed = true);
      await Future<void>.delayed(const Duration(milliseconds: 420));
      if (mounted) {
        _openResults();
      }
    } catch (error) {
      if (mounted) {
        _rotationController.stop();
        setState(() => _scanError = error);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _runRealScan() async {
    switch (widget.target) {
      case ScanLaunchTarget.smartScan:
        refreshSmartScan(ref);
        ref.invalidate(smartScanProvider);
        await ref.read(smartScanProvider.future);
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
    }
  }

  void _openResults() {
    final String destination = switch (widget.target) {
      ScanLaunchTarget.smartScan => AppRoutes.clean,
      ScanLaunchTarget.screenshots => AppRoutes.screenshotCleaner,
      ScanLaunchTarget.duplicates => AppRoutes.duplicates,
      ScanLaunchTarget.largeVideos => AppRoutes.videos,
    };
    if (widget.target == ScanLaunchTarget.smartScan) {
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
  };

  String _statusFor(double progress) {
    if (_completed || progress >= 0.995) {
      return 'Scan complete';
    }
    if (progress < 0.3) {
      return 'Reading storage';
    }
    if (progress < 0.62) {
      return 'Analyzing files';
    }
    if (progress < 0.9) {
      return 'Calculating recoverable space';
    }
    return 'Finishing the real device scan';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final Listenable animation = Listenable.merge(<Listenable>[
      _progressController,
      _completionController,
      _rotationController,
    ]);

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
        child: AnimatedBuilder(
          animation: animation,
          builder: (BuildContext context, Widget? child) {
            final double progress = _progress.clamp(0, 1);
            return SingleChildScrollView(
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
                    'Reviewing files safely on this device.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: isDark
                          ? theme.colorScheme.onSurfaceVariant
                          : HomeUpperStyle.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  _PremiumScanRing(
                    key: const Key('scan_progress_ring'),
                    progress: progress,
                    rotation: _rotationController.value,
                    completed: _completed,
                    isDark: isDark,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _scanError == null
                        ? _ScanStatusCard(
                            key: ValueKey<String>(_statusFor(progress)),
                            progress: progress,
                            status: _statusFor(progress),
                            isDark: isDark,
                          )
                        : _ScanErrorCard(
                            onRetry: _startScan,
                            onCancel: () => context.go(AppRoutes.home),
                          ),
                  ),
                ],
              ),
            );
          },
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

class _PremiumScanRing extends StatelessWidget {
  const _PremiumScanRing({
    required this.progress,
    required this.rotation,
    required this.completed,
    required this.isDark,
    super.key,
  });

  final double progress;
  final double rotation;
  final bool completed;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final int percent = (progress * 100).round().clamp(0, 100);
    return Semantics(
      value: '$percent percent',
      label: 'Storage scan progress',
      child: SizedBox.square(
        dimension: 228,
        child: CustomPaint(
          painter: _PremiumScanPainter(
            progress: progress,
            rotation: rotation,
            completed: completed,
            isDark: isDark,
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: completed
                  ? const Icon(
                      Icons.check_rounded,
                      key: Key('scan_complete_icon'),
                      size: 68,
                      color: AppColors.success,
                    )
                  : Text(
                      '$percent%',
                      key: const Key('scan_progress_percent'),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : HomeUpperStyle.textPrimary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.8,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PremiumScanPainter extends CustomPainter {
  const _PremiumScanPainter({
    required this.progress,
    required this.rotation,
    required this.completed,
    required this.isDark,
  });

  final double progress;
  final double rotation;
  final bool completed;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final Rect glowRect = Rect.fromCircle(
      center: center,
      radius: size.width * 0.47,
    );
    final Rect progressRect = Rect.fromCircle(
      center: center,
      radius: size.width * 0.405,
    );

    canvas.drawCircle(
      center,
      size.width * 0.465,
      Paint()
        ..color = isDark
            ? AppColors.darkPrimary.withValues(alpha: 0.07)
            : HomeUpperStyle.primaryBlue.withValues(alpha: 0.055)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      size.width * 0.405,
      Paint()
        ..color = isDark
            ? AppColors.darkBorder.withValues(alpha: 0.75)
            : const Color(0xFFE4EBF8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 15,
    );

    final Paint progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: <Color>[
          HomeUpperStyle.deepBlue,
          HomeUpperStyle.primaryBlue,
          HomeUpperStyle.radarCyan,
          HomeUpperStyle.deepBlue,
        ],
      ).createShader(progressRect);
    canvas.drawArc(
      progressRect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      progressPaint,
    );

    if (!completed) {
      final double angle = -math.pi / 2 + rotation * math.pi * 2;
      final Paint glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: <Color>[
            Colors.transparent,
            HomeUpperStyle.radarCyan.withValues(alpha: 0.2),
            HomeUpperStyle.radarCyan,
          ],
          stops: const <double>[0, 0.72, 1],
          transform: GradientRotation(angle),
        ).createShader(glowRect);
      canvas.drawArc(glowRect, angle, math.pi * 0.58, false, glowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PremiumScanPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.rotation != rotation ||
        oldDelegate.completed != completed ||
        oldDelegate.isDark != isDark;
  }
}

class _ScanStatusCard extends StatelessWidget {
  const _ScanStatusCard({
    required this.progress,
    required this.status,
    required this.isDark,
    super.key,
  });

  final double progress;
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
              value: progress,
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
