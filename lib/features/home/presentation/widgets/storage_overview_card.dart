import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';
import 'package:mobile_cleaner/app/theme/app_tokens.dart';
import 'package:mobile_cleaner/core/ui/app_card.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/storage/domain/storage_info.dart';
import 'package:mobile_cleaner/features/storage/presentation/providers/storage_overview_provider.dart';

/// Storage Overview: the first and most important card on Home.
///
/// ## Layout
///
/// Two-column hierarchy. Left: the used percentage, the single number that
/// answers "how full am I?", large and blue. Right: a ring whose centre
/// carries the figure a person acts on next — how much space is left.
/// A compact `used / total` summary sits underneath as context.
///
/// ## Wording
///
/// "Internal storage" rather than "Total storage". What Android reports is
/// the usable internal partition, which is always smaller than the number
/// printed on the box — a 128 GB phone reports about 118 GB. Calling that
/// "Total" invites the user to think the app is miscounting.
///
/// No calculation changed: every figure still comes straight from
/// [StorageInfo].
class StorageOverviewCard extends ConsumerWidget {
  const StorageOverviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<StorageInfo> storage = ref.watch(storageOverviewProvider);

    return AppCard(
      child: storage.when(
        loading: () => const _LoadingStorage(),
        error: (Object error, StackTrace stackTrace) => _StorageError(
          onRetry: () => ref.invalidate(storageOverviewProvider),
        ),
        data: (StorageInfo info) => _StorageDetails(info: info),
      ),
    );
  }
}

class _StorageDetails extends StatelessWidget {
  const _StorageDetails({required this.info});

  final StorageInfo info;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Storage Overview',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: <Widget>[
            // Left column: the headline percentage.
            Expanded(
              child: Semantics(
                label: '${info.usedPercentage} percent of storage used',
                child: Column(
                  key: const Key('used_storage'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${info.usedPercentage}%',
                        key: const Key('storage_percentage'),
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontSize: 44,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                          color: colors.primary,
                          height: 1.05,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Used',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Right column: the ring, with available space at its centre.
            _StorageRing(info: info),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.sm),
        Row(
          key: const Key('total_storage'),
          children: <Widget>[
            Icon(Icons.storage_rounded, size: 16, color: colors.onSurfaceVariant),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                'Internal storage',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            // Separate Text widgets so each real figure stays individually
            // verifiable in tests.
            Text(
              ByteFormatter.format(info.usedBytes),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              ' / ',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            Text(
              ByteFormatter.format(info.totalBytes),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The storage ring: mostly blue, a small orange accent at the head of the
/// used arc, and a light gray track for the unused remainder.
///
/// The blue and orange segments together are exactly [StorageInfo.usedFraction]
/// of the circle — the accent restyles the tip of the real value, it never
/// adds to it.
class _StorageRing extends StatelessWidget {
  const _StorageRing({required this.info});

  final StorageInfo info;

  static const double _size = 118;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;

    return Semantics(
      label:
          '${ByteFormatter.format(info.freeBytes)} of storage available',
      child: SizedBox.square(
        dimension: _size,
        child: CustomPaint(
          painter: _StorageRingPainter(
            usedFraction: info.usedFraction,
            usedColor: colors.primary,
            accentColor: AppColors.accentOrange,
            trackColor: isDark
                ? Colors.white.withValues(alpha: 0.10)
                : AppColors.border,
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  key: const Key('free_storage'),
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      ByteFormatter.format(info.freeBytes),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Available',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StorageRingPainter extends CustomPainter {
  const _StorageRingPainter({
    required this.usedFraction,
    required this.usedColor,
    required this.accentColor,
    required this.trackColor,
  });

  final double usedFraction;
  final Color usedColor;
  final Color accentColor;
  final Color trackColor;

  static const double _stroke = 11;
  static const double _startAngle = -math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = (math.min(size.width, size.height) - _stroke) / 2;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);

    Paint stroke(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;

    // Unused remainder: a full, very light track underneath.
    canvas.drawArc(rect, 0, math.pi * 2, false, stroke(trackColor));

    final double used = usedFraction.clamp(0.0, 1.0);
    if (used <= 0) {
      return;
    }

    final double usedSweep = math.pi * 2 * used;
    // A small accent at the head of the used arc — capped so it always reads
    // as an accent, and skipped entirely when the arc is too short for it.
    final double accentSweep = usedSweep > 0.5
        ? math.min(usedSweep * 0.16, math.pi * 2 * 0.055)
        : 0.0;
    final double blueSweep = usedSweep - accentSweep;

    canvas.drawArc(rect, _startAngle, blueSweep, false, stroke(usedColor));
    if (accentSweep > 0) {
      canvas.drawArc(
        rect,
        _startAngle + blueSweep,
        accentSweep,
        false,
        stroke(accentColor),
      );
    }
  }

  @override
  bool shouldRepaint(_StorageRingPainter oldDelegate) {
    return oldDelegate.usedFraction != usedFraction ||
        oldDelegate.usedColor != usedColor ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.trackColor != trackColor;
  }
}

class _LoadingStorage extends StatelessWidget {
  const _LoadingStorage();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 220,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _StorageError extends StatelessWidget {
  const _StorageError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.storage_rounded,
            size: 44,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'Storage information is unavailable',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
