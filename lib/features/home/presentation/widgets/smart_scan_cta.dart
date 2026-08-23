import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';
import 'package:mobile_cleaner/app/theme/app_tokens.dart';

/// The Smart Scan hero: the strongest action card on Home.
///
/// One deep-blue card so there is never a question about what to do first.
/// The left side names the feature, explains it in one line, and carries the
/// compact white CTA; the right side is a quiet scanner motif built from
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
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Material(
            color: Colors.transparent,
            child: Ink(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[AppColors.primary, AppColors.primaryDeep],
                ),
              ),
              child: InkWell(
                key: const Key('smart_scan_hero'),
                onTap: onScan,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints constraints) {
                      // The decorative motif earns its space only when there
                      // is comfortably room for it.
                      final bool showMotif = constraints.maxWidth >= 300;

                      return Row(
                        children: <Widget>[
                          Expanded(child: _HeroCopy(onScan: onScan)),
                          if (showMotif) ...<Widget>[
                            const SizedBox(width: AppSpacing.sm),
                            const ExcludeSemantics(
                              child: SizedBox.square(
                                dimension: 92,
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
        const SizedBox(height: AppSpacing.xs + 2),
        // The subtle trust cue, deliberately not visually dominant.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.lock_outline_rounded,
              size: 14,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'Files stay on your device.',
                key: const Key('smart_scan_privacy_note'),
                maxLines: 2,
                style: theme.textTheme.bodySmall?.copyWith(
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
              size: 18,
              color: Colors.white,
            ),
            const SizedBox(width: AppSpacing.xs),
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
        const SizedBox(height: 6),
        Text(
          'Find and clean junk files to free up space.',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.85),
            height: 1.35,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          key: const Key('smart_scan_button'),
          onPressed: onScan,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: AppColors.primaryDeep,
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.tile),
            ),
          ),
          icon: const Icon(Icons.search_rounded, size: 18),
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

    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    for (final (double factor, double alpha) in <(double, double)>[
      (0.34, 0.30),
      (0.62, 0.20),
      (0.92, 0.12),
    ]) {
      ring.color = Colors.white.withValues(alpha: alpha);
      canvas.drawCircle(center, radius * factor, ring);
    }

    // One thin radial line, as if mid-sweep.
    const double angle = -math.pi / 3.2;
    final Offset tip = center +
        Offset(math.cos(angle), math.sin(angle)) * (radius * 0.92);
    canvas.drawLine(
      center,
      tip,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.38)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );

    // A few highlight points on the rings.
    final Paint dot = Paint()..color = Colors.white.withValues(alpha: 0.85);
    canvas.drawCircle(center, 3, dot);
    for (final (double factor, double dotAngle, double dotRadius)
        in <(double, double, double)>[
      (0.62, -math.pi / 3.2, 2.6),
      (0.92, math.pi / 7, 2.2),
      (0.34, math.pi * 0.78, 1.8),
    ]) {
      final Offset position = center +
          Offset(math.cos(dotAngle), math.sin(dotAngle)) * (radius * factor);
      canvas.drawCircle(position, dotRadius, dot);
    }
  }

  @override
  bool shouldRepaint(_ScannerMotifPainter oldDelegate) => false;
}
