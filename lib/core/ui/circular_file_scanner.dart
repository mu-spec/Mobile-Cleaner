import 'package:flutter/material.dart';
import 'package:phone_storage_cleaner/core/ui/reference_progress_art.dart';

/// Silent, presentation-only scan activity. Null [progress] means indeterminate.
///
/// Only pass a fraction supplied by the scanner, never an elapsed-time estimate.
/// This widget has no timers, completion callbacks, or access to scan providers.
/// A fraction of one completes the current stage's arc, not the parent scan.
class CircularFileScanner extends StatefulWidget {
  const CircularFileScanner({
    this.progress,
    this.cleaning = false,
    this.scanId,
    this.stageId,
    this.active = true,
    this.completed = false,
    this.succeeded = false,
    this.size = 228,
    this.presentationBuilder,
    super.key,
  }) : assert(progress == null || (progress >= 0 && progress <= 1)),
       assert(size > 0);

  final double? progress;
  final bool cleaning;

  /// Change for a genuinely new scan; updates within one scan never rewind.
  final Object? scanId;

  /// Reset only for a genuinely different selected stage, not a count update.
  final Object? stageId;
  final bool active;
  final bool completed;

  /// Entire operation succeeded, independently of the completion transition.
  final bool succeeded;
  final double size;

  /// Optional surrounding scan presentation. Receives this exact animated
  /// measured fill so the external number, arc and bar cannot drift apart.
  /// Cleaning does not use this and keeps its independently approved layout.
  final Widget Function(
    BuildContext,
    Widget radar,
    double? fill,
    Animation<double> motion,
  )?
  presentationBuilder;

  // Slow continuous radar rotation; independent of measured work.
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
    // A stage may fill its ring; only completed renders the parent checkmark.
    if (next != null && next > _confirmed) {
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
    final double? progress = widget.completed
        ? 1
        : widget.progress == null
        ? null
        : _confirmed;
    final radar = Semantics(
      key: const Key('scan_progress_semantics'),
      label: widget.cleaning
          ? 'Cleaning progress'
          : widget.stageId == null
          ? 'Scan progress'
          : 'Current stage progress',
      value: widget.completed
          ? 'Scan complete'
          : progress != null
          ? '${(progress * 100).floor()} percent'
          : widget.active
          ? (widget.cleaning ? 'Cleaning' : 'Scanning')
          : (widget.cleaning ? 'Cleaning paused' : 'Scan paused'),
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: widget.size,
          child: RepaintBoundary(
            key: const Key('circular_file_scanner_artwork'),
            child: CustomPaint(
              key: const Key('circular_file_scanner_paint'),
              painter: ReferenceProgressPainter(
                motion: _motion,
                fill: progress == null
                    ? const AlwaysStoppedAnimation(0.0)
                    : _fill,
                cleaning: widget.cleaning,
                completed: widget.completed,
              ),
              child: Center(
                child: widget.completed
                    ? Icon(
                        Icons.check_rounded,
                        key: const Key('scan_complete_icon'),
                        size: widget.size * .25,
                        color: ReferenceProgressColors.white,
                      )
                    : SizedBox(
                        key: Key(
                          widget.cleaning
                              ? 'cleaning_broom_art'
                              : 'scan_radar_center',
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
    final builder = widget.presentationBuilder;
    if (builder == null) return radar;
    return AnimatedBuilder(
      animation: _fill,
      builder: (context, _) => builder(
        context,
        radar,
        progress == null ? null : _fill.value.clamp(0.0, _confirmed),
        _motion,
      ),
    );
  }
}
