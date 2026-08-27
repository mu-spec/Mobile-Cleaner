import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Paints the premium scanning radar used by the Home hero card.
///
/// The sweep is deliberately drawn as a short fading sector instead of
/// rotating the whole illustration. Targets remain anchored and pulse as the
/// beam passes them, which makes the motion feel like a scan rather than a
/// spinning decorative icon.
class RadarPainter extends CustomPainter {
  const RadarPainter({required this.rotation, this.progress = 1.0});

  /// Normalized turns in the range 0–1.
  final double rotation;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final double opacity = progress.clamp(0.0, 1.0);
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double maxRadius = math.min(size.width, size.height) * 0.39;
    final Rect radarBounds = Rect.fromCircle(center: center, radius: maxRadius);
    final double sweepAngle = rotation * math.pi * 2 - math.pi / 2;

    _drawGlassSurface(canvas, center, maxRadius, opacity);
    _drawGrid(canvas, center, maxRadius, opacity);
    _drawSweep(canvas, center, radarBounds, maxRadius, sweepAngle, opacity);
    _drawTargets(canvas, center, maxRadius, sweepAngle, opacity);
    _drawHub(canvas, center, opacity);
  }

  void _drawGlassSurface(
    Canvas canvas,
    Offset center,
    double radius,
    double opacity,
  ) {
    final Rect haloBounds = Rect.fromCircle(center: center, radius: radius + 9);
    final Paint halo = Paint()
      ..shader = const RadialGradient(
        colors: <Color>[
          Color(0x1AFFFFFF),
          Color(0x0D8BE5FF),
          Color(0x00FFFFFF),
        ],
        stops: <double>[0, 0.72, 1],
      ).createShader(haloBounds);
    canvas.drawCircle(center, radius + 9, halo);

    final Paint surface = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.24, -0.28),
        colors: <Color>[
          Colors.white.withValues(alpha: 0.10 * opacity),
          const Color(0xFF65D6FF).withValues(alpha: 0.035 * opacity),
          Colors.white.withValues(alpha: 0.018 * opacity),
        ],
        stops: const <double>[0, 0.62, 1],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, surface);
  }

  void _drawGrid(Canvas canvas, Offset center, double radius, double opacity) {
    final Paint grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = Colors.white.withValues(alpha: 0.24 * opacity);

    for (int ring = 1; ring <= 3; ring++) {
      canvas.drawCircle(center, radius * ring / 3, grid);
    }

    final Paint crosshair = Paint()
      ..strokeWidth = 0.65
      ..color = Colors.white.withValues(alpha: 0.10 * opacity);
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      crosshair,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      crosshair,
    );

    final Paint rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..color = Colors.white.withValues(alpha: 0.32 * opacity);
    canvas.drawCircle(center, radius, rim);
  }

  void _drawSweep(
    Canvas canvas,
    Offset center,
    Rect bounds,
    double radius,
    double angle,
    double opacity,
  ) {
    const int segments = 14;
    const double sweepWidth = math.pi * 0.42;
    final double segmentWidth = sweepWidth / segments;

    // Several narrow sectors create a smooth angular fade without making the
    // whole radar rotate as one flat object.
    for (int segment = 0; segment < segments; segment++) {
      final double strength = (segment + 1) / segments;
      final double start = angle - sweepWidth + segment * segmentWidth;
      final Path sector = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(bounds, start, segmentWidth + 0.012, false)
        ..close();
      final Paint sectorPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0xFF8BE5FF)
            .withValues(alpha: (0.006 + strength * strength * 0.115) * opacity);
      canvas.drawPath(sector, sectorPaint);
    }

    final Offset tip = Offset(
      center.dx + math.cos(angle) * radius,
      center.dy + math.sin(angle) * radius,
    );
    final Paint beamGlow = Paint()
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF8BE5FF).withValues(alpha: 0.20 * opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawLine(center, tip, beamGlow);

    final Paint beam = Paint()
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..shader = ui.Gradient.linear(center, tip, <Color>[
        Colors.white.withValues(alpha: 0.95 * opacity),
        const Color(0xFF8BE5FF).withValues(alpha: 0.74 * opacity),
      ]);
    canvas.drawLine(center, tip, beam);

    final Paint tipGlow = Paint()
      ..color = Colors.white.withValues(alpha: 0.78 * opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(tip, 2.6, tipGlow);
  }

  void _drawTargets(
    Canvas canvas,
    Offset center,
    double radius,
    double sweepAngle,
    double opacity,
  ) {
    const List<double> angles = <double>[0.18, 1.02, 2.08, 2.78, 3.92, 5.16];
    const List<double> distances = <double>[0.74, 0.45, 0.70, 0.38, 0.82, 0.58];

    for (int index = 0; index < angles.length; index++) {
      final double targetAngle = angles[index];
      final double distance = radius * distances[index];
      final Offset target = Offset(
        center.dx + math.cos(targetAngle) * distance,
        center.dy + math.sin(targetAngle) * distance,
      );
      final double delta = _angularDistance(targetAngle, sweepAngle);
      final double beamResponse = (1 - delta / 0.48).clamp(0.0, 1.0);
      final double ambientPulse =
          (math.sin(rotation * math.pi * 4 + index * 1.37) + 1) / 2;
      final double emphasis = math.max(beamResponse, ambientPulse * 0.28);

      if (emphasis > 0.12) {
        final Paint targetGlow = Paint()
          ..color = const Color(0xFFB9EEFF)
              .withValues(alpha: (0.12 + emphasis * 0.24) * opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
        canvas.drawCircle(target, 4 + emphasis * 2, targetGlow);
      }

      final Paint targetPaint = Paint()
        ..color = Colors.white.withValues(
          alpha: (0.48 + emphasis * 0.46) * opacity,
        );
      canvas.drawCircle(target, 1.7 + emphasis * 1.15, targetPaint);
    }
  }

  void _drawHub(Canvas canvas, Offset center, double opacity) {
    final Paint hubGlow = Paint()
      ..color = const Color(0xFF8BE5FF).withValues(alpha: 0.34 * opacity)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
    canvas.drawCircle(center, 9, hubGlow);

    final Paint hubRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.48 * opacity);
    canvas.drawCircle(center, 6.5, hubRing);

    final Paint hub = Paint()
      ..color = Colors.white.withValues(alpha: 0.96 * opacity);
    canvas.drawCircle(center, 3.2, hub);
  }

  double _angularDistance(double a, double b) {
    double delta = (a - b).abs() % (math.pi * 2);
    if (delta > math.pi) {
      delta = math.pi * 2 - delta;
    }
    return delta;
  }

  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) {
    return oldDelegate.rotation != rotation || oldDelegate.progress != progress;
  }
}
