import 'dart:math' as math;
import 'package:flutter/material.dart';

class RadarPainter extends CustomPainter {
  const RadarPainter({required this.rotation, this.progress = 1.0})
      : super(repaint: AlwaysStoppedAnimation(rotation));

  final double rotation; // 0-1 for full circle
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint circlePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.white.withValues(alpha: 0.35);

    final Paint beamPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.7);

    final Offset center = Offset(size.width / 2, size.height / 2);
    final double maxR = math.min(size.width, size.height) / 2 * 0.82;

    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(center, maxR * (i / 4), circlePaint);
    }

    final List<double> dotAngles = <double>[
      math.pi * 0.15, math.pi * 0.55, math.pi * 0.85,
      math.pi * 1.35, math.pi * 1.75, math.pi * 2.25,
    ];
    for (int i = 0; i < dotAngles.length; i++) {
      final double angle = dotAngles[i];
      final double r = maxR * (0.35 + (i % 3) * 0.22);
      final Offset dot = Offset(
        center.dx + math.cos(angle) * r,
        center.dy + math.sin(angle) * r,
      );
      final Paint dotPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.white.withValues(alpha: 0.55 + (i % 2) * 0.35);
      canvas.drawCircle(dot, 2.2 + (i % 2) * 1.0, dotPaint);
    }

    final Paint centerGlow = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white.withValues(alpha: 0.9);
    canvas.drawCircle(center, 4, centerGlow);

    final Paint glowSoft = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawCircle(center, 10, glowSoft..color = Colors.white.withValues(alpha: 0.35));

    final double angle = rotation * math.pi * 2 - math.pi / 2;
    final Offset tip = Offset(
      center.dx + math.cos(angle) * maxR,
      center.dy + math.sin(angle) * maxR,
    );
    canvas.drawLine(center, tip, beamPaint);

    final Paint tipGlow = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(tip, 2.5, tipGlow..color = Colors.white.withValues(alpha: 0.8));
  }

  @override
  bool shouldRepaint(covariant RadarPainter old) {
    return old.rotation != rotation || old.progress != progress;
  }
}
