import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Sampled from the supplied JPEG, not from the application's theme. The
/// original is compressed/annotated; these are median unmarked 5px patches.
abstract final class ReferenceProgressColors {
  static const royal = Color(0xFF3367ED);
  static const blue = Color(0xFF164AD3);
  static const deep = Color(0xFF032C99);
  static const cyan = Color(0xFF49C4F3);
  static const ice = Color(0xFFB4DFFE);
  static const ring = Color(0xFFCEDAF5);
  static const halo = Color(0xFFEFF2FB);
  static const orange = Color(0xFFF79516);
  static const white = Color(0xFFF4FBFC);
}

/// Approved scan geometry: center .342, cyan lip .398, progress .405,
/// pale rings .427/.444/.45 and halo .49 of the total diameter.
/// Cleaning retains its separately approved smaller rim and .375 progress radius.
/// Motion is decorative only; the orange arc never depends on [motion].
class ReferenceProgressPainter extends CustomPainter {
  ReferenceProgressPainter({
    required this.motion,
    required this.fill,
    this.cleaning = false,
    this.completed = false,
  }) : super(repaint: Listenable.merge([motion, fill]));
  final Animation<double> motion;
  final Animation<double> fill;
  final bool cleaning;
  final bool completed;

  @override
  void paint(Canvas canvas, Size size) {
    final d = size.shortestSide;
    final c = size.center(Offset.zero);
    final phase = motion.value * math.pi * 2;
    void disc(double radius, Paint paint) =>
        canvas.drawCircle(c, d * radius, paint);
    final paint = Paint();
    if (!cleaning) {
      disc(
        .49,
        Paint()..color = ReferenceProgressColors.halo.withValues(alpha: .65),
      );
    }
    disc(
      .49,
      paint
        ..shader = const RadialGradient(
          colors: [Color(0x0049C4F3), Color(0x28CEDAF5), Color(0x00EFF2FB)],
          stops: [0, .8, 1],
        ).createShader(Rect.fromCircle(center: c, radius: d * .49)),
    );
    paint.shader = null;
    disc(
      .45,
      paint..color = ReferenceProgressColors.halo.withValues(alpha: .65),
    );
    disc(
      cleaning ? .411 : .444,
      paint..color = ReferenceProgressColors.ring.withValues(alpha: .58),
    );
    disc(
      cleaning ? .386 : .427,
      paint
        ..color = Colors.white
        ..shader =
            const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                ReferenceProgressColors.ice,
                ReferenceProgressColors.ring,
                ReferenceProgressColors.halo,
              ],
            ).createShader(
              Rect.fromCircle(center: c, radius: d * (cleaning ? .386 : .427)),
            ),
    );
    disc(
      cleaning ? .366 : .398,
      paint
        ..color = Colors.white
        ..shader =
            LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: cleaning
                  ? const [
                      ReferenceProgressColors.ice,
                      ReferenceProgressColors.cyan,
                      ReferenceProgressColors.blue,
                      ReferenceProgressColors.ice,
                    ]
                  : const [
                      ReferenceProgressColors.cyan,
                      ReferenceProgressColors.blue,
                      ReferenceProgressColors.royal,
                      ReferenceProgressColors.blue,
                    ],
            ).createShader(
              Rect.fromCircle(center: c, radius: d * (cleaning ? .366 : .398)),
            ),
    );
    disc(
      .342,
      paint
        ..color = Colors.white
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ReferenceProgressColors.royal,
            ReferenceProgressColors.blue,
            ReferenceProgressColors.deep,
          ],
          stops: [0, .42, 1],
        ).createShader(Rect.fromCircle(center: c, radius: d * .342)),
    );
    paint.shader = null;
    // The reference has a soft directional cyan lip, not a generic radar grid.
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: d * (cleaning ? .35 : .365)),
      cleaning ? -math.pi : math.pi * .7,
      cleaning ? math.pi * .65 : math.pi * .95,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = d * (cleaning ? .018 : .034)
        ..color = ReferenceProgressColors.cyan.withValues(
          alpha: cleaning ? .5 : .95,
        )
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, d * .014),
    );
    if (!cleaning) {
      for (final radius in [.155, .245, .32]) {
        disc(
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = d * .0025
            ..color = ReferenceProgressColors.ice.withValues(alpha: .16),
        );
      }
      final grid = Paint()
        ..strokeWidth = d * .002
        ..color = ReferenceProgressColors.ice.withValues(alpha: .10);
      canvas.drawLine(c - Offset(d * .32, 0), c + Offset(d * .32, 0), grid);
      canvas.drawLine(c - Offset(0, d * .32), c + Offset(0, d * .32), grid);
    }
    // Exact measured bounds; a rounded cap would overpaint unconfirmed work.
    if (fill.value > 0) {
      final rect = Rect.fromCircle(
        center: c,
        radius: d * (cleaning ? .375 : .405),
      );
      final sweep = math.pi * 2 * fill.value;
      final start = cleaning ? -math.pi / 6 : -math.pi / 2;
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = d * (cleaning ? .046 : .06)
          ..color = ReferenceProgressColors.orange.withValues(alpha: .3)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, d * .016),
      );
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = d * (cleaning ? .036 : .05)
          ..strokeCap = StrokeCap.butt
          ..color = ReferenceProgressColors.orange,
      );
    }
    if (completed) return; // Parent-success check is drawn by the widget.
    if (cleaning) {
      final pulse = .65 + .35 * math.sin(phase);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.scale(d / 228);
      canvas.rotate(.27);
      final white = Paint()..color = ReferenceProgressColors.white;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-4, -39, 9, 37),
          const Radius.circular(5),
        ),
        white,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-22, -9, 44, 10),
          const Radius.circular(5),
        ),
        white,
      );
      final bristles = Path()
        ..moveTo(-21, 6)
        ..lineTo(21, 6)
        ..lineTo(30, 34)
        ..quadraticBezierTo(25, 42, 18, 36)
        ..quadraticBezierTo(12, 43, 5, 38)
        ..quadraticBezierTo(-2, 44, -9, 38)
        ..quadraticBezierTo(-17, 41, -23, 34)
        ..quadraticBezierTo(-31, 36, -30, 28)
        ..close();
      canvas.drawPath(bristles, white);
      for (final x in [-16.0, -5.0, 6.0, 17.0]) {
        canvas.drawLine(
          Offset(x, 17),
          Offset(x + 4, 34),
          Paint()
            ..strokeWidth = 1.4
            ..strokeCap = StrokeCap.round
            ..color = ReferenceProgressColors.ring,
        );
      }
      canvas.restore();
      for (final offset in [
        const Offset(-.2, -.18),
        const Offset(-.19, .23),
        const Offset(.22, .15),
      ]) {
        _spark(
          canvas,
          c + offset * d,
          d * .022,
          ReferenceProgressColors.white.withValues(alpha: pulse * .7),
        );
      }
    } else {
      // One fine illuminated beam, with a luminous point at its origin.
      final angle = -math.pi / 4 + phase;
      final end = c + Offset(math.cos(angle), math.sin(angle)) * d * .377;
      canvas.drawLine(
        c,
        end,
        Paint()
          ..strokeWidth = d * .014
          ..color = ReferenceProgressColors.ice.withValues(alpha: .55)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, d * .009),
      );
      canvas.drawLine(
        c,
        end,
        Paint()
          ..strokeWidth = d * .005
          ..strokeCap = StrokeCap.round
          ..color = ReferenceProgressColors.white,
      );
      disc(
        .05,
        Paint()
          ..color = ReferenceProgressColors.cyan
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, d * .018),
      );
      disc(
        .035,
        Paint()
          ..shader = RadialGradient(
            colors: [
              ReferenceProgressColors.cyan,
              ReferenceProgressColors.cyan.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: c, radius: d * .035)),
      );
      disc(.014, Paint()..color = ReferenceProgressColors.white);
      for (final p in [
        const Offset(-.18, -.155),
        const Offset(-.035, -.21),
        const Offset(.225, -.165),
        const Offset(.195, -.045),
        const Offset(-.145, .15),
        const Offset(-.205, .21),
        const Offset(.13, .245),
      ]) {
        _spark(
          canvas,
          c + p * d,
          d * .012,
          ReferenceProgressColors.ice.withValues(alpha: .55),
        );
      }
    }
  }

  void _spark(Canvas canvas, Offset c, double r, Color color) {
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy - r)
        ..lineTo(c.dx + r * .3, c.dy - r * .3)
        ..lineTo(c.dx + r, c.dy)
        ..lineTo(c.dx + r * .3, c.dy + r * .3)
        ..lineTo(c.dx, c.dy + r)
        ..lineTo(c.dx - r * .3, c.dy + r * .3)
        ..lineTo(c.dx - r, c.dy)
        ..lineTo(c.dx - r * .3, c.dy - r * .3)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant ReferenceProgressPainter oldDelegate) =>
      oldDelegate.motion != motion ||
      oldDelegate.fill != fill ||
      oldDelegate.cleaning != cleaning ||
      oldDelegate.completed != completed;
}

/// Reference orange/blue bar. Null is unknown activity: no guessed fill.
class ReferenceProgressBar extends StatelessWidget {
  const ReferenceProgressBar({required this.value, super.key});
  final double? value;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Confirmed work progress',
    value: value == null
        ? 'Total unknown'
        : '${(value! * 100).floor()} percent',
    child: SizedBox(
      height: 6,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            children: [
              const Positioned.fill(
                child: ColoredBox(color: ReferenceProgressColors.ring),
              ),
              if (value != null && value! > 0)
                SizedBox(
                  width: constraints.maxWidth * value!,
                  height: 6,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          ReferenceProgressColors.orange,
                          ReferenceProgressColors.orange,
                          ReferenceProgressColors.blue,
                        ],
                        stops: [0, .88, 1],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
