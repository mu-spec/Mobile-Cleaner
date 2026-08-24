import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mobile_cleaner/app/theme/app_tokens.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/home_upper_style.dart';

/// The Smart Scan hero: the strongest action card on Home.
///
/// One deep-blue card so there is never a question about what to do first.
/// The left side names the feature, explains it in two short lines, and
/// carries the compact white CTA; the right side is a scanner motif built from
/// plain shapes — decoration only, no fake progress, no animation.
///
/// The privacy line sits directly under the card rather than in Settings or
/// a policy page. A storage cleaner asks for broad file access, and the
/// moment the user is deciding whether to let it scan is exactly when the
/// reassurance is worth something. It is also true of this build: the app
/// has no INTERNET permission at all.
///
/// Both the card and the CTA route through the same existing [onScan]
/// callback — navigation and scan behaviour are unchanged.
class SmartScanCta extends StatelessWidget {
  const SmartScanCta({required this.onScan, super.key});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Column(
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(HomeUpperStyle.heroRadius),
          child: Material(
            color: Colors.transparent,
            child: Ink(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    HomeUpperStyle.deepBlue,
                    HomeUpperStyle.primaryBlue,
                  ],
                ),
              ),
              child: InkWell(
                key: const Key('smart_scan_hero'),
                onTap: onScan,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints constraints) {
                      final double textScale = MediaQuery.textScalerOf(
                        context,
                      ).scale(1);
                      // Decoration yields to content on narrow layouts and at
                      // accessibility text sizes.
                      final bool showMotif =
                          constraints.maxWidth >= 280 && textScale <= 1.3;

                      return Row(
                        children: <Widget>[
                          Expanded(child: _HeroCopy(onScan: onScan)),
                          if (showMotif) ...<Widget>[
                            const SizedBox(width: AppSpacing.xs),
                            const ExcludeSemantics(
                              child: SizedBox.square(
                                key: Key('smart_scan_artwork'),
                                dimension: 72,
                                child: CustomPaint(
                                  painter: _ScannerMotifPainter(),
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        // The subtle trust cue, deliberately not visually dominant.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.shield_outlined,
              size: 12,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                'Your files stay on your device',
                key: const Key('smart_scan_privacy_note'),
                maxLines: 2,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 10,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Title, supporting copy, and the compact white CTA.
class _HeroCopy extends StatelessWidget {
  const _HeroCopy({required this.onScan});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(
              Icons.auto_awesome_rounded,
              size: 15,
              color: HomeUpperStyle.orange,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Smart Scan',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Find and clean junk files\nto free up space.',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.85),
            height: 1.25,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        FilledButton.icon(
          key: const Key('smart_scan_button'),
          onPressed: onScan,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: HomeUpperStyle.deepBlue,
            minimumSize: const Size(0, 38),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.tile),
            ),
          ),
          icon: const Icon(Icons.search_rounded, size: 16),
          label: const Text('Scan Now'),
        ),
      ],
    );
  }
}

/// A static scanner/radar suggestion: concentric circles, one thin radial
/// line, and a few highlight points. Subtle by design — low-alpha white on
/// the hero's own blue, no animation, no fake data.
class _ScannerMotifPainter extends CustomPainter {
  const _ScannerMotifPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = math.min(size.width, size.height) / 2;
    const Color cyan = HomeUpperStyle.radarCyan;

    // A quiet field gives the motif enough presence without reading as a
    // progress indicator or a glow effect.
    canvas.drawCircle(
      center,
      radius * 0.94,
      Paint()..color = cyan.withValues(alpha: 0.06),
    );

    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    for (final (double factor, Color color) in <(double, Color)>[
      (0.30, cyan.withValues(alpha: 0.52)),
      (0.55, Colors.white.withValues(alpha: 0.28)),
      (0.78, cyan.withValues(alpha: 0.30)),
      (0.96, Colors.white.withValues(alpha: 0.16)),
    ]) {
      ring.color = color;
      canvas.drawCircle(center, radius * factor, ring);
    }

    // A short orange arc echoes cleanup/recoverable storage without implying
    // any measured scan progress.
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.78),
      math.pi * 0.08,
      math.pi * 0.34,
      false,
      Paint()
        ..color = HomeUpperStyle.orange.withValues(alpha: 0.92)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );

    const double angle = -math.pi / 3.1;
    final Offset tip = center +
        Offset(math.cos(angle), math.sin(angle)) * (radius * 0.92);
    canvas.drawLine(
      center,
      tip,
      Paint()
        ..color = cyan.withValues(alpha: 0.78)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );

    final Paint whiteDot = Paint()
      ..color = Colors.white.withValues(alpha: 0.92);
    final Paint cyanDot = Paint()..color = cyan.withValues(alpha: 0.92);
    canvas.drawCircle(center, 2.8, whiteDot);
    for (final (double factor, double dotAngle, double dotRadius, Paint paint)
        in <(double, double, double, Paint)>[
      (0.55, angle, 2.5, cyanDot),
      (0.96, math.pi / 6, 2.0, whiteDot),
      (0.78, math.pi * 0.77, 1.7, cyanDot),
      (0.30, math.pi * 1.25, 1.5, whiteDot),
    ]) {
      final Offset position = center +
          Offset(math.cos(dotAngle), math.sin(dotAngle)) * (radius * factor);
      canvas.drawCircle(position, dotRadius, paint);
    }
  }

  @override
  bool shouldRepaint(_ScannerMotifPainter oldDelegate) => false;
}
