import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_cleaner/app/theme/app_colors.dart';
import 'package:mobile_cleaner/app/theme/app_tokens.dart';
import 'package:mobile_cleaner/core/utils/byte_formatter.dart';
import 'package:mobile_cleaner/features/home/domain/cleanup_score.dart';
import 'package:mobile_cleaner/features/home/presentation/providers/recommendations_provider.dart';
import 'package:mobile_cleaner/features/home/presentation/widgets/home_upper_style.dart';
import 'package:phosphor_icons/phosphor_icons.dart';

/// Compact Home explanation of the most recently completed Smart Scan.
class CleanupScoreCard extends ConsumerWidget {
  const CleanupScoreCard({required this.onOpen, super.key});

  final ValueChanged<CleanupOpportunityKind> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<CompletedCleanupAnalysis?> analysis = ref.watch(
      cleanupAnalysisProvider,
    );

    return analysis.when(
      loading: () => const _UnavailableScore(
        message: 'Calculating from your Smart Scan…',
        loading: true,
      ),
      error: (_, _) => const _UnavailableScore(
        message: 'Run Smart Scan to calculate your score',
      ),
      data: (CompletedCleanupAnalysis? result) => result == null
          ? const _UnavailableScore(
              message: 'Run Smart Scan to calculate your score',
            )
          : _CompletedScore(score: result.score, onOpen: onOpen),
    );
  }
}

class _UnavailableScore extends StatelessWidget {
  const _UnavailableScore({required this.message, this.loading = false});

  final String message;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    return Card(
      key: const Key('cleanup_score_unscanned'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: dark
                    ? AppColors.darkInfoSurface
                    : HomeUpperStyle.softBlue,
                borderRadius: BorderRadius.circular(13),
              ),
              alignment: Alignment.center,
              child: loading
                  ? const SizedBox(
                      width: 21,
                      height: 21,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const PhosphorIcon(
                      PhosphorIconsDuotone.chartDonut,
                      size: 25,
                      color: HomeUpperStyle.primaryBlue,
                      duotoneSecondaryColor: HomeUpperStyle.orange,
                      duotoneSecondaryOpacity: 0.72,
                    ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'Cleanup Score',
                    key: const Key('cleanup_score_title'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: dark
                          ? theme.colorScheme.onSurface
                          : AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    key: const Key('cleanup_score_message'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.25,
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

class _CompletedScore extends StatelessWidget {
  const _CompletedScore({required this.score, required this.onOpen});

  final CleanupScore score;
  final ValueChanged<CleanupOpportunityKind> onOpen;

  Color _scoreColor(BuildContext context) {
    if (score.value >= CleanupScoreCalculator.excellentMinimum) {
      return AppColors.success;
    }
    if (score.value >= CleanupScoreCalculator.goodMinimum) {
      return Theme.of(context).brightness == Brightness.dark
          ? AppColors.darkPrimary
          : HomeUpperStyle.primaryBlue;
    }
    return Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkOrange
        : HomeUpperStyle.orange;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color scoreColor = _scoreColor(context);

    return Card(
      key: const Key('cleanup_score_card'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Semantics(
                  label: 'Cleanup score ${score.value} out of 100',
                  child: SizedBox(
                    key: const Key('cleanup_score_ring'),
                    width: 72,
                    height: 72,
                    child: Stack(
                      alignment: Alignment.center,
                      children: <Widget>[
                        SizedBox.expand(
                          child: CircularProgressIndicator(
                            value: score.value / 100,
                            strokeWidth: 7,
                            strokeCap: StrokeCap.round,
                            backgroundColor: scoreColor.withValues(alpha: 0.13),
                            color: scoreColor,
                          ),
                        ),
                        Text(
                          '${score.value}',
                          key: const Key('cleanup_score_value'),
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: scoreColor,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Cleanup Score',
                        key: const Key('cleanup_score_title'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: dark
                              ? theme.colorScheme.onSurface
                              : AppColors.navy,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${score.value} / 100  ·  ${score.label.label}',
                        key: const Key('cleanup_score_label'),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scoreColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        score.opportunityBytes == 0
                            ? 'Your storage looks clean'
                            : '${ByteFormatter.format(score.opportunityBytes)} '
                                  'cleanup opportunities',
                        key: const Key('cleanup_score_opportunities'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (score.breakdown.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
              const SizedBox(height: AppSpacing.sm),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  const double gap = AppSpacing.xs;
                  final double width = (constraints.maxWidth - gap) / 2;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: <Widget>[
                      for (final CleanupScoreBreakdown item in score.breakdown)
                        SizedBox(
                          width: width,
                          child: _BreakdownTile(
                            item: item,
                            onTap: () => onOpen(item.kind),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BreakdownTile extends StatelessWidget {
  const _BreakdownTile({required this.item, required this.onTap});

  final CleanupScoreBreakdown item;
  final VoidCallback onTap;

  IconData get _icon => switch (item.kind) {
    CleanupOpportunityKind.exactDuplicates => PhosphorIconsDuotone.copy,
    CleanupOpportunityKind.apkInstallers => PhosphorIconsDuotone.androidLogo,
    CleanupOpportunityKind.oldDownloads => PhosphorIconsDuotone.downloadSimple,
    CleanupOpportunityKind.oldScreenshots => PhosphorIconsDuotone.imageSquare,
    CleanupOpportunityKind.largeVideos => PhosphorIconsDuotone.videoCamera,
    CleanupOpportunityKind.largeFiles => PhosphorIconsDuotone.fileArrowDown,
  };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;

    return Material(
      color: dark
          ? AppColors.darkInfoSurface.withValues(alpha: 0.72)
          : HomeUpperStyle.softBlue.withValues(alpha: 0.68),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: Key('cleanup_score_breakdown_${item.kind.name}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          child: Row(
            children: <Widget>[
              PhosphorIcon(
                _icon,
                size: 20,
                color: HomeUpperStyle.primaryBlue,
                duotoneSecondaryColor: HomeUpperStyle.orange,
                duotoneSecondaryOpacity: 0.62,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      ByteFormatter.format(item.bytes),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              PhosphorIcon(
                PhosphorIconsRegular.caretRight,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
