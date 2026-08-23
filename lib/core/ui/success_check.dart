import 'package:flutter/material.dart';

/// The success mark shown after a completed cleanup.
///
/// Scales and fades in once, then stops.
///
/// ## Why it must finish
///
/// A looping or infinitely-repeating animation never lets the widget tree
/// reach a steady state, and `tester.pumpAndSettle()` waits forever — it would
/// hang every widget test that reaches this screen. This plays exactly once
/// and then holds its final frame, so the tree settles.
///
/// It also honours [MediaQueryData.disableAnimations], so a user who has
/// turned animations off in Android accessibility settings gets the final
/// frame immediately rather than motion they asked not to see.
class SuccessCheck extends StatefulWidget {
  const SuccessCheck({
    this.size = 96,
    this.duration = const Duration(milliseconds: 450),
    super.key,
  });

  final double size;
  final Duration duration;

  @override
  State<SuccessCheck> createState() => _SuccessCheckState();
}

class _SuccessCheckState extends State<SuccessCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    // MediaQuery below is the single accessibility decision point. Preserve
    // the requested duration here so a test or nested MediaQuery that enables
    // motion is not silently shortened by the binding-level platform flag.
    animationBehavior: AnimationBehavior.preserve,
  );

  late final Animation<double> _scale = CurvedAnimation(
    parent: _controller,
    // Overshoots slightly then settles, which reads as a confirmation rather
    // than a plain fade.
    curve: Curves.easeOutBack,
  );

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;

    if (MediaQuery.disableAnimationsOf(context)) {
      // Jump straight to the finished state.
      _controller.value = 1;
      return;
    }

    // Start after the initial frame so the zero-progress state is actually
    // painted once. Starting during dependency resolution can let a test or a
    // busy first frame consume the whole short animation before it is visible.
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (mounted) {
        _controller.forward(from: 0);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return FadeTransition(
      opacity: _fade,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          key: const Key('success_check'),
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_rounded,
            size: widget.size * 0.54,
            color: colors.primary,
          ),
        ),
      ),
    );
  }
}
