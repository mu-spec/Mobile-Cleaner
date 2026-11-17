import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phone_storage_cleaner/app/theme/app_colors.dart';
import 'package:phone_storage_cleaner/features/home/presentation/widgets/home_upper_style.dart';

/// Silent, presentation-only scan activity. Null [progress] means indeterminate.
///
/// Only pass a fraction supplied by the scanner, never an elapsed-time estimate.
/// This widget has no timers, completion callbacks, or access to scan providers.
class CircularFileScanner extends StatefulWidget {
  const CircularFileScanner({
    this.progress,
    this.scanId,
    this.active = true,
    this.completed = false,
    this.succeeded = false,
    this.size = 228,
    super.key,
  }) : assert(progress == null || (progress >= 0 && progress <= 1)),
       assert(size > 0);

  final double? progress;

  /// Change for a genuinely new scan; updates within one scan never rewind.
  final Object? scanId;
  final bool active;
  final bool completed;

  /// Entire operation succeeded, independently of the completion transition.
  final bool succeeded;
  final double size;

  // Four former 1450 ms wave cycles: a deliberately slower, gentle orbit.
  static const Duration motionDuration = Duration(milliseconds: 5800);

  @override
  State<CircularFileScanner> createState() => _CircularFileScannerState();
}

class _CircularFileScannerState extends State<CircularFileScanner>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: CircularFileScanner.motionDuration,
  );
  late final AnimationController _fill = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  double _confirmed = 0;
  bool _visible = true;
  bool _reduceMotion = false;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final AppLifecycleState? lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _acceptProgress();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncMotion();
  }

  @override
  void didUpdateWidget(CircularFileScanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scanId != widget.scanId) {
      _confirmed = 0;
      _fill.value = 0;
    }
    _acceptProgress();
    _syncMotion();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncMotion();
  }

  void _acceptProgress() {
    final next = widget.completed || widget.succeeded ? 1.0 : widget.progress;
    // A child reaching its total is not authorization to finish the ring.
    if (next != null &&
        (next < 1 || widget.completed || widget.succeeded) &&
        next > _confirmed) {
      _confirmed = next;
    }
  }

  void _syncMotion() {
    if (_visible && _foreground) {
      if (_reduceMotion || !widget.active || widget.completed) {
        _fill.value = _confirmed;
      } else if (_fill.value < _confirmed) {
        _fill.animateTo(_confirmed, curve: Curves.easeOutCubic);
      }
    } else {
      _fill.stop();
    }
    final bool shouldAnimate =
        widget.active &&
        !widget.completed &&
        _visible &&
        _foreground &&
        !_reduceMotion;
    if (shouldAnimate) {
      if (!_motion.isAnimating) {
        _motion.repeat();
      }
    } else {
      _motion.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _motion.dispose();
    _fill.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final double? progress = widget.completed
        ? 1
        : widget.progress == null
        ? null
        : _confirmed;
    return Semantics(
      key: const Key('scan_progress_semantics'),
      label: 'Scan progress',
      value: widget.completed
          ? 'Scan complete'
          : progress != null
          ? '${(progress * 100).floor()} percent'
          : widget.active
          ? 'Scanning'
          : 'Scan paused',
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: widget.size,
          child: RepaintBoundary(
            key: const Key('circular_file_scanner_artwork'),
            child: CustomPaint(
              key: const Key('circular_file_scanner_paint'),
              painter: _FileScannerPainter(
                motion: _motion,
                fill: _fill,
                completed: widget.completed,
                blue: dark ? AppColors.darkPrimary : HomeUpperStyle.primaryBlue,
                orange: dark ? AppColors.darkOrange : HomeUpperStyle.orange,
                surface: dark ? AppColors.darkSurface : Colors.white,
                track: dark ? AppColors.darkBorder : HomeUpperStyle.softBlue,
              ),
              child: Center(
                child: Icon(
                  widget.completed ? Icons.check_rounded : Icons.folder_rounded,
                  key: widget.completed
                      ? const Key('scan_complete_icon')
                      : const Key('scan_folder_icon'),
                  size: widget.size * 0.28,
                  color: dark
                      ? AppColors.darkPrimary
                      : HomeUpperStyle.primaryBlue,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FileScannerPainter extends CustomPainter {
  _FileScannerPainter({
    required this.motion,
    required this.fill,
    required this.completed,
    required this.blue,
    required this.orange,
    required this.surface,
    required this.track,
  }) : super(repaint: Listenable.merge([motion, fill]));

  final Animation<double> motion;
  final Animation<double> fill;
  final bool completed;
  final Color blue;
  final Color orange;
  final Color surface;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final double side = math.min(size.width, size.height);
    final Offset center = size.center(Offset.zero);
    final double radius = side * 0.43;
    final Rect ring = Rect.fromCircle(center: center, radius: radius);
    final double phase = motion.value;
    const double start = -math.pi / 2;
    final double sweep = math.pi * 2 * fill.value;
    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = side * 0.032
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, Paint()..color = surface);
    canvas.drawCircle(center, radius, stroke..color = track);
    if (sweep > 0) {
      // Round end caps can overlap the remaining gap before 100%, or paint
      // beyond the confirmed angle. Keep the blue sweep inside its exact
      // measured bounds; the orange leading marker preserves the soft tip.
      canvas.drawArc(
        ring,
        start,
        sweep,
        false,
        stroke
          ..color = blue
          ..strokeCap = StrokeCap.butt,
      );
    }
    if (!completed) {
      // In determinate mode the orange marker follows actual progress.
      final double angle = start + sweep;
      final Offset marker =
          center + Offset(math.cos(angle), math.sin(angle)) * radius;
      canvas.drawCircle(marker, side * 0.023, Paint()..color = orange);

      for (int index = 0; index < 4; index++) {
        final double t = (phase + index / 4) % 1;
        final double eased = Curves.easeInOutSine.transform(t);
        final double distance = side * (0.31 - 0.23 * eased);
        final double angle = -math.pi * 0.75 + index * math.pi / 2;
        final Offset position =
            center + Offset(math.cos(angle), math.sin(angle)) * distance;
        // Fade completely at both ends so the repeating path never jumps.
        final double opacity =
            math.pow(math.sin(math.pi * t), 2).toDouble() * 0.8;
        final double scale = side / 228 * (1 - 0.24 * eased);
        canvas.save();
        canvas.translate(position.dx, position.dy);
        canvas.scale(scale);
        _paintFileIcon(canvas, index, blue.withValues(alpha: opacity));
        canvas.restore();
      }
    }
    // The stable folder sits on a quiet surface, in front of incoming files.
    canvas.drawCircle(center, side * 0.17, Paint()..color = surface);
  }

  @override
  bool shouldRepaint(covariant _FileScannerPainter oldDelegate) =>
      oldDelegate.motion != motion ||
      oldDelegate.fill != fill ||
      oldDelegate.completed != completed ||
      oldDelegate.blue != blue ||
      oldDelegate.orange != orange ||
      oldDelegate.surface != surface ||
      oldDelegate.track != track;

  // Tiny vector icons avoid text layout, image decoding, and extra layers.
  void _paintFileIcon(Canvas canvas, int index, Color color) {
    final Paint line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Rect box = const Rect.fromLTRB(-10, -9, 10, 9);
    switch (index) {
      case 0: // Photos.
        canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(3)),
          line,
        );
        canvas.drawCircle(const Offset(4, -3), 1.5, line);
        canvas.drawPath(
          Path()
            ..moveTo(-9, 6)
            ..lineTo(-3, 0)
            ..lineTo(1, 4)
            ..lineTo(4, 1)
            ..lineTo(9, 6),
          line,
        );
      case 1: // Videos.
        canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(3)),
          line,
        );
        canvas.drawPath(
          Path()
            ..moveTo(-2, -4)
            ..lineTo(4, 0)
            ..lineTo(-2, 4)
            ..close(),
          line,
        );
      case 2: // Audio files, a visual only; never produces sound.
        canvas.drawPath(
          Path()
            ..moveTo(-4, 5)
            ..lineTo(-4, -6)
            ..lineTo(7, -9)
            ..lineTo(7, 2),
          line,
        );
        canvas.drawOval(const Rect.fromLTRB(-10, 3, -4, 8), line);
        canvas.drawOval(const Rect.fromLTRB(1, 0, 7, 5), line);
      case 3: // Documents.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(-8, -11, 8, 11),
            const Radius.circular(2),
          ),
          line,
        );
        for (final double y in <double>[-4, 1, 6]) {
          canvas.drawLine(Offset(-4, y), Offset(4, y), line);
        }
    }
  }
}
