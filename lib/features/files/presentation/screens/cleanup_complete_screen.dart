import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';
import 'package:mobile_cleaner/core/ui/success_check.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
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
    await Clipboard.setData(ClipboardData(text: summary));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cleanup summary copied. Share it anywhere.'),
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
          const _CelebrationSparkle(
            alignment: Alignment(-0.82, -0.72),
            color: AppColors.cleanupOrange,
            size: 7,
          ),
          const _CelebrationSparkle(
            alignment: Alignment(0.8, -0.66),
            color: AppColors.actionBlue,
            size: 8,
          ),
          const _CelebrationSparkle(
            alignment: Alignment(-0.72, -0.12),
            color: AppColors.actionBlue,
            size: 6,
          ),
          const _CelebrationSparkle(
            alignment: Alignment(0.7, 0.02),
            color: AppColors.cleanupOrange,
            size: 6,
          ),
          const _CelebrationSparkle(
            alignment: Alignment(-0.55, 0.62),
            color: Color(0xFF7DC7E8),
            size: 8,
          ),
          const _CelebrationSparkle(
            alignment: Alignment(0.58, 0.7),
            color: AppColors.actionBlue,
            size: 7,
          ),
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

class _CelebrationSparkle extends StatelessWidget {
  const _CelebrationSparkle({
    required this.alignment,
    required this.color,
    required this.size,
  });

  final Alignment alignment;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Transform.rotate(
        angle: 0.78,
        child: Container(width: size, height: size, color: color),
      ),
    );
  }
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
          const SizedBox(width: 5),
          Icon(
            Icons.chevron_right_rounded,
            size: 19,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
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
