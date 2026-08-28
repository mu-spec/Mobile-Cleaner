import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';
import 'package:mobile_cleaner/core/ui/success_check.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/files/data/cleanup_share_service.dart';
import 'package:mobile_cleaner/features/files/domain/delete_result.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Final stage of the shared cleanup flow.
///
/// Every figure is taken from [DeleteResult], so partial platform failures can
/// never inflate the number of items removed or the amount of space freed.
class CleanupCompleteScreen extends StatelessWidget {
  const CleanupCompleteScreen({
    required this.result,
    this.cleanupDuration = Duration.zero,
    this.onDone,
    super.key,
  });

  final DeleteResult result;
  final Duration cleanupDuration;
  final VoidCallback? onDone;

  void _finish(BuildContext context) {
    if (onDone case final VoidCallback callback) {
      callback();
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _share(BuildContext context) async {
    final String summary =
        'Mobile Cleaner removed ${result.deletedCount} '
        '${result.deletedCount == 1 ? 'item' : 'items'} and freed '
        '${ByteFormatter.format(result.freedBytes)}.';
    final bool opened = await CleanupShareService().shareCleanupSummary(
      summary,
    );
    if (!opened) {
      await Clipboard.setData(ClipboardData(text: summary));
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No share app opened, so the summary was copied.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool partial = result.failureCount > 0;

    return Scaffold(
      key: const Key('cleanup_complete_screen'),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                children: <Widget>[
                  _CelebrationCard(result: result, partial: partial),
                  const SizedBox(height: 16),
                  _CleanupDetailsCard(
                    result: result,
                    cleanupDuration: cleanupDuration,
                  ),
                  if (partial) ...<Widget>[
                    const SizedBox(height: 14),
                    _PartialNotice(result: result),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
              child: Column(
                children: <Widget>[
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      key: const Key('cleanup_done'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.brandBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => _finish(context),
                      child: const Text('Done'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton.icon(
                      key: const Key('cleanup_share'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.brandBlue,
                        side: const BorderSide(color: AppColors.brandBlue),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => _share(context),
                      icon: const Icon(PhosphorIconsDuotone.shareFat, size: 21),
                      label: const Text('Share'),
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

class _CelebrationCard extends StatelessWidget {
  const _CelebrationCard({required this.result, required this.partial});

  final DeleteResult result;
  final bool partial;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      key: const Key('cleanup_celebration_card'),
      height: 260,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const <Color>[Color(0xFF172238), Color(0xFF201B18)]
              : const <Color>[Color(0xFFFFF7EB), Color(0xFFFFFCF7)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: dark ? AppColors.darkBorder : const Color(0xFFFFE7C3),
        ),
      ),
      child: Stack(
        children: <Widget>[
          const Positioned.fill(child: _PremiumParticleCelebration()),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SuccessCheck(size: 70),
                const SizedBox(height: 16),
                Text(
                  ByteFormatter.format(result.freedBytes),
                  key: const Key('cleanup_storage_recovered'),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppColors.cleanupOrange,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  partial ? 'Cleanup Partly Complete' : 'Cleaned Successfully!',
                  key: const Key('cleanup_title'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 7),
                Text(
                  partial
                      ? 'Some selected items still need your attention.'
                      : 'More space for the things that matter.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumParticleCelebration extends StatefulWidget {
  const _PremiumParticleCelebration();

  @override
  State<_PremiumParticleCelebration> createState() =>
      _PremiumParticleCelebrationState();
}

class _PremiumParticleCelebrationState
    extends State<_PremiumParticleCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
    animationBehavior: AnimationBehavior.preserve,
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
      _controller.value = 1;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (mounted) {
          _controller.forward(from: 0);
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: const Key('cleanup_particles'),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) => CustomPaint(
          painter: _CelebrationParticlePainter(progress: _controller.value),
        ),
      ),
    );
  }
}

class _CelebrationParticlePainter extends CustomPainter {
  const _CelebrationParticlePainter({required this.progress});

  final double progress;

  static const List<Color> _colors = <Color>[
    AppColors.cleanupOrange,
    Color(0xFFFFB13B),
    AppColors.actionBlue,
    AppColors.brandBlue,
    Color(0xFF70C6E8),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final double burst = Curves.easeOutCubic.transform(
      (progress / 0.72).clamp(0, 1),
    );
    final double fadeStart = ((progress - 0.58) / 0.42).clamp(0, 1);
    final double opacity = 1 - Curves.easeIn.transform(fadeStart);
    if (opacity <= 0) {
      return;
    }

    final Offset origin = Offset(size.width / 2, size.height * 0.29);
    for (int index = 0; index < 30; index++) {
      final double angle = -math.pi + (index * 2.399963229728653);
      final double distance = 48 + ((index * 37) % 86).toDouble();
      final double drift = ((index % 5) - 2) * 8 * progress;
      final Offset position = Offset(
        origin.dx + math.cos(angle) * distance * burst + drift,
        origin.dy +
            math.sin(angle) * distance * burst +
            54 * progress * progress,
      );
      final double particleSize = 3.5 + (index % 4) * 1.2;
      final Paint paint = Paint()
        ..color = _colors[index % _colors.length].withValues(
          alpha: opacity * (index.isEven ? 0.95 : 0.72),
        );

      canvas.save();
      canvas.translate(position.dx, position.dy);
      canvas.rotate(angle + progress * (2.4 + (index % 3)));
      if (index % 3 == 0) {
        canvas.drawCircle(Offset.zero, particleSize / 2, paint);
      } else {
        final RRect piece = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: particleSize,
            height: particleSize * 1.8,
          ),
          const Radius.circular(1.5),
        );
        canvas.drawRRect(piece, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CelebrationParticlePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _CleanupDetailsCard extends StatelessWidget {
  const _CleanupDetailsCard({
    required this.result,
    required this.cleanupDuration,
  });

  final DeleteResult result;
  final Duration cleanupDuration;

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: dark ? AppColors.darkSurfaceElevated : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: dark ? AppColors.darkBorder : AppColors.border,
        ),
      ),
      child: Column(
        children: <Widget>[
          _DetailRow(
            icon: PhosphorIconsDuotone.trash,
            label: 'Items Removed',
            value:
                '${result.deletedCount} '
                '${result.deletedCount == 1 ? 'item' : 'items'}',
            valueKey: const Key('cleanup_files_deleted'),
          ),
          const Divider(height: 1, indent: 52),
          _DetailRow(
            icon: PhosphorIconsDuotone.clockCounterClockwise,
            label: 'Space Freed',
            value: ByteFormatter.format(result.freedBytes),
          ),
          const Divider(height: 1, indent: 52),
          _DetailRow(
            icon: PhosphorIconsDuotone.clock,
            label: 'Time Saved',
            value: _formatDuration(cleanupDuration),
            valueKey: const Key('cleanup_time_saved'),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueKey,
  });

  final IconData icon;
  final String label;
  final String value;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: AppColors.brandBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            value,
            key: valueKey,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _PartialNotice extends StatelessWidget {
  const _PartialNotice({required this.result});

  final DeleteResult result;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Container(
      key: const Key('cleanup_partial_notice'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            PhosphorIconsDuotone.warning,
            size: 21,
            color: colors.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${result.failureCount} '
              '${result.failureCount == 1 ? 'item' : 'items'} could not be '
              'cleaned. ${result.failures.first.reason}',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onErrorContainer, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final int seconds = duration.inSeconds.clamp(1, 3599);
  final int minutes = seconds ~/ 60;
  final int remaining = seconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:'
      '${remaining.toString().padLeft(2, '0')}';
}
