import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/app/route_observer.dart';
import 'package:mobile_cleaner/app/theme/app_tokens.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/home_upper_style.dart';
import 'package:mobile_cleaner/features/storage/domain/storage_info.dart';
import 'package:mobile_cleaner/features/storage/presentation/providers/storage_overview_provider.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

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
      elevation: isDark ? 0 : 2,
      shadowColor: HomeUpperStyle.navy.withValues(alpha: 0.08),
      surfaceTintColor: Colors.transparent,
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
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
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
                        key: const Key('storage_used_percentage'),
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
            _StorageRing(info: info),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        _StorageSummaryBar(info: info),
      ],
    );
  }
}

/// Reference-style compact storage strip with a real usage indicator.
class _StorageSummaryBar extends StatelessWidget {
  const _StorageSummaryBar({required this.info});

  final StorageInfo info;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;
    final double usedFraction = info.usedFraction.clamp(0.0, 1.0);

    return Semantics(
      label: 'Internal storage usage',
      value:
          '${ByteFormatter.format(info.usedBytes)} of ${ByteFormatter.format(info.totalBytes)} used',
      child: Container(
        key: const Key('total_storage'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? <Color>[
                    HomeUpperStyle.primaryBlue.withValues(alpha: 0.18),
                    HomeUpperStyle.primaryBlue.withValues(alpha: 0.08),
                  ]
                : const <Color>[Color(0xFFF1F7FF), Color(0xFFEAF2FF)],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? HomeUpperStyle.iconBlueSecondary.withValues(alpha: 0.16)
                : HomeUpperStyle.primaryBlue.withValues(alpha: 0.09),
          ),
        ),
        child: Row(
          children: <Widget>[
            SizedBox.square(
              dimension: 32,
              child: Center(
                child: PhosphorIcon(
                  key: const Key('storage_database_icon'),
                  PhosphorIconsDuotone.database,
                  size: 24,
                  color: HomeUpperStyle.deepBlue,
                  duotoneSecondaryColor: HomeUpperStyle.iconBlueSecondary,
                  duotoneSecondaryOpacity: 0.72,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  FittedBox(
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
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          ' / ',
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
                  const SizedBox(height: 1),
                  Text(
                    'Internal storage',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 9.5,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    key: const Key('storage_usage_track'),
                    height: 5,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.10)
                          : Colors.white.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      key: const Key('storage_usage_fill'),
                      widthFactor: usedFraction,
                      heightFactor: 1,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: <Color>[
                              HomeUpperStyle.primaryBlue,
                              HomeUpperStyle.deepBlue,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two-colour donut: blue is the real used fraction and orange is the real
/// available fraction. Together they always fill exactly 360 degrees.
class _StorageRing extends StatefulWidget {
  const _StorageRing({required this.info});

  final StorageInfo info;

  @override
  State<_StorageRing> createState() => _StorageRingState();
}

class _StorageRingState extends State<_StorageRing> {
  int _replayEpoch = 0;

  @override
  void initState() {
    super.initState();
    storageRingReplay.addListener(_replay);
  }

  @override
  void didUpdateWidget(covariant _StorageRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.info.usedFraction != widget.info.usedFraction) {
      _replayEpoch++;
    }
  }

  void _replay() {
    if (mounted) {
      setState(() => _replayEpoch++);
    }
  }

  @override
  void dispose() {
    storageRingReplay.removeListener(_replay);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;
    final bool reducedMotion = MediaQuery.disableAnimationsOf(context);
    final double targetFraction = widget.info.usedFraction
        .clamp(0.0, 1.0)
        .toDouble();
    final Color usedColor = isDark
        ? colors.primary
        : HomeUpperStyle.primaryBlue;

    final Widget ringContent = Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            key: const Key('free_storage'),
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                ByteFormatter.format(widget.info.freeBytes),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.35,
                  color: usedColor,
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
    );

    if (reducedMotion) {
      return Semantics(
        label:
            '${ByteFormatter.format(widget.info.freeBytes)} of storage available',
        child: SizedBox.square(
          dimension: 112,
          child: CustomPaint(
            key: const Key('storage_ring_paint'),
            painter: _StorageRingPainter(
              usedFraction: targetFraction,
              usedColor: usedColor,
              availableColor: HomeUpperStyle.orange,
            ),
            child: ringContent,
          ),
        ),
      );
    }

    return Semantics(
      label:
          '${ByteFormatter.format(widget.info.freeBytes)} of storage available',
      child: SizedBox.square(
        dimension: 112,
        child: TweenAnimationBuilder<double>(
          key: ValueKey<int>(_replayEpoch),
          tween: Tween<double>(begin: 0, end: targetFraction),
          // Keep the fill visible long enough to read on a physical device.
          // Ease in and out so it grows gently instead of jumping ahead in
          // the first few frames like the old ease-out curve did.
          duration: const Duration(milliseconds: 2400),
          curve: Curves.easeInOutCubic,
          builder:
              (BuildContext context, double animatedFraction, Widget? child) {
                return CustomPaint(
                  key: const Key('storage_ring_paint'),
                  painter: _StorageRingPainter(
                    usedFraction: animatedFraction,
                    usedColor: usedColor,
                    availableColor: HomeUpperStyle.orange,
                  ),
                  child: child,
                );
              },
          child: ringContent,
        ),
      ),
    );
  }
}

class _StorageRingPainter extends CustomPainter {
  _StorageRingPainter({
    required this.usedFraction,
    required this.usedColor,
    required this.availableColor,
  });

  final double usedFraction;
  final Color usedColor;
  final Color availableColor;

  static const double _stroke = 11.5;
  static const double _startAngle = -math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = (math.min(size.width, size.height) - _stroke - 6) / 2;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);
    final double used = usedFraction.clamp(0.0, 1.0);

    final Paint innerGlass = Paint()
      ..shader =
          RadialGradient(
            colors: <Color>[
              usedColor.withValues(alpha: 0.018),
              usedColor.withValues(alpha: 0.055),
            ],
          ).createShader(
            Rect.fromCircle(center: center, radius: radius - _stroke / 2 - 1),
          );
    canvas.drawCircle(center, radius - _stroke / 2 - 1, innerGlass);

    final Paint ringShadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke + 1.5
      ..color = HomeUpperStyle.navy.withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(center, radius, ringShadow);

    final Shader availableShader = SweepGradient(
      transform: const GradientRotation(_startAngle),
      colors: <Color>[
        Color.lerp(availableColor, Colors.white, 0.28)!,
        availableColor,
        Color.lerp(availableColor, HomeUpperStyle.navy, 0.10)!,
        Color.lerp(availableColor, Colors.white, 0.28)!,
      ],
    ).createShader(rect);
    final Shader usedShader = SweepGradient(
      transform: const GradientRotation(_startAngle),
      colors: <Color>[
        Color.lerp(usedColor, Colors.white, 0.24)!,
        usedColor,
        Color.lerp(usedColor, HomeUpperStyle.deepBlue, 0.34)!,
        Color.lerp(usedColor, Colors.white, 0.24)!,
      ],
    ).createShader(rect);

    Paint stroke(Shader shader) => Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      // Butt caps preserve the exact blue/orange data boundary.
      ..strokeCap = StrokeCap.butt;

    // Orange owns the complete circle first; blue replaces exactly the real
    // used fraction. No gray/white track or decorative third segment exists.
    canvas.drawArc(
      rect,
      _startAngle,
      math.pi * 2,
      false,
      stroke(availableShader),
    );
    if (used > 0) {
      canvas.drawArc(
        rect,
        _startAngle,
        math.pi * 2 * used,
        false,
        stroke(usedShader),
      );
    }

    final Paint innerHighlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.white.withValues(alpha: 0.32);
    canvas.drawCircle(center, radius - _stroke / 2, innerHighlight);
  }

  @override
  bool shouldRepaint(covariant _StorageRingPainter oldDelegate) {
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
