import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/app/theme/app_tokens.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/home_duotone_icon.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/home_upper_style.dart';
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
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;

    return Card(
      key: const Key('storage_overview_card'),
      elevation: isDark ? 0 : 1,
      shadowColor: HomeUpperStyle.navy.withValues(alpha: 0.06),
      color: isDark
          ? theme.colorScheme.surfaceContainerHigh
          : HomeUpperStyle.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HomeUpperStyle.storageRadius),
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : HomeUpperStyle.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Storage Overview',
              key: const Key('storage_overview_title'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: isDark
                    ? theme.colorScheme.onSurface
                    : HomeUpperStyle.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            storage.when(
              loading: () => const _LoadingStorage(),
              error: (Object error, StackTrace stackTrace) => _StorageError(
                onRetry: () => ref.invalidate(storageOverviewProvider),
              ),
              data: (StorageInfo info) => _StorageDetails(info: info),
            ),
          ],
        ),
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
    final bool isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
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
                          fontSize: 38,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                          color: isDark
                              ? colors.primary
                              : HomeUpperStyle.primaryBlue,
                          height: 1.05,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Storage used',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            // Right column: the ring, with available space at its centre.
            _StorageRing(info: info),
          ],
        ),
        const SizedBox(height: 6),
        const Divider(height: 1),
        const SizedBox(height: 6),
        Row(
          key: const Key('total_storage'),
          children: <Widget>[
            HomeDuotoneIcon(
              icon: PhosphorIconsDuotone.database,
              primaryColor: HomeUpperStyle.iconBluePrimary,
              secondaryColor: HomeUpperStyle.iconBlueSecondary,
              backgroundColor: isDark
                  ? HomeUpperStyle.iconBluePrimary.withValues(alpha: 0.22)
                  : HomeUpperStyle.softBlue,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      ByteFormatter.format(info.usedBytes),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: colors.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      ' of ',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      ByteFormatter.format(info.totalBytes),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                'Internal storage',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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

/// Two-colour donut: blue is the real used fraction and orange is the real
/// available fraction. Together they always fill exactly 360 degrees.
class _StorageRing extends StatelessWidget {
  const _StorageRing({required this.info});

  final StorageInfo info;

  static const double _size = 112;

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
            usedColor: isDark ? colors.primary : HomeUpperStyle.primaryBlue,
            availableColor: HomeUpperStyle.orange,
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  key: const Key('free_storage'),
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      ByteFormatter.format(info.freeBytes),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Available',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 9,
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
    required this.availableColor,
  });

  final double usedFraction;
  final Color usedColor;
  final Color availableColor;

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
      // Butt caps keep blue + orange equal to exactly one full circle.
      ..strokeCap = StrokeCap.butt;

    final double used = usedFraction.clamp(0.0, 1.0);

    // Orange owns the complete circle first; blue replaces exactly the real
    // used fraction. No gray/white track or decorative third segment exists.
    canvas.drawArc(
      rect,
      _startAngle,
      math.pi * 2,
      false,
      stroke(availableColor),
    );
    if (used > 0) {
      canvas.drawArc(
        rect,
        _startAngle,
        math.pi * 2 * used,
        false,
        stroke(usedColor),
      );
    }
  }

  @override
  bool shouldRepaint(_StorageRingPainter oldDelegate) {
    return oldDelegate.usedFraction != usedFraction ||
        oldDelegate.usedColor != usedColor ||
        oldDelegate.availableColor != availableColor;
  }
}

class _LoadingStorage extends StatelessWidget {
  const _LoadingStorage();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 100,
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
      height: 150,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.storage_rounded,
            size: 36,
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
